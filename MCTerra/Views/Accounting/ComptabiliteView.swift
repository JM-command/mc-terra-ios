//
//  ComptabiliteView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

/// Revenue dashboard for a chosen month: a month selector at the top, the month's
/// total, a breakdown per payment method, and the paid sessions of that month.
/// CSV and PDF exports of the selected month are available from the toolbar.
struct ComptabiliteView: View {
    /// All finished sessions, most recent first. Filtering on the stored status
    /// string keeps the SwiftData predicate simple; month scoping happens in-view.
    @Query(
        filter: #Predicate<Seance> { $0.status == "terminee" },
        sort: \Seance.date,
        order: .reverse
    )
    private var seances: [Seance]

    /// Whether the dashboard scopes data to a month or a whole year.
    @State private var mode: AccountingScope = .month

    /// The month currently shown. Defaults to the current month.
    @State private var month = AccountingMonth(containing: .now)

    /// The year currently shown. Defaults to the current year.
    @State private var year = AccountingYear(containing: .now)

    /// Finished sessions that fall inside the selected month.
    private var monthSeances: [Seance] {
        seances.filter { month.contains($0.date) }
    }

    /// The subset of the month that carries a payment method (paid sessions), used
    /// for both the list and the exports.
    private var monthPaidSeances: [Seance] {
        monthSeances.filter { !$0.paymentMethod.isEmpty }
    }

    /// Finished sessions that fall inside the selected year.
    private var yearSeances: [Seance] {
        seances.filter { year.contains($0.date) }
    }

    /// The subset of the year that carries a payment method, used for exports.
    private var yearPaidSeances: [Seance] {
        yearSeances.filter { !$0.paymentMethod.isEmpty }
    }

    var body: some View {
        List {
            ScopePickerSection(mode: $mode)

            switch mode {
            case .month:
                monthContent
            case .year:
                yearContent
            }
        }
        .navigationTitle("Comptabilité")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch mode {
                case .month:
                    ExportMenu(seances: monthPaidSeances, month: month)
                case .year:
                    YearExportMenu(seances: yearPaidSeances, year: year)
                }
            }
        }
    }

    // MARK: - Month content

    @ViewBuilder
    private var monthContent: some View {
        MonthSelectorSection(month: $month)

        if monthSeances.isEmpty {
            emptyMonthSection
        } else {
            RevenueTotalsSection(seances: monthSeances)
            PaymentBreakdownSection(seances: monthSeances)
            MonthPaymentsSection(seances: monthPaidSeances)
        }
    }

    // MARK: - Year content

    @ViewBuilder
    private var yearContent: some View {
        YearSelectorSection(year: $year)

        if yearSeances.isEmpty {
            emptyYearSection
        } else {
            YearTotalsSection(seances: yearSeances)
            PaymentBreakdownSection(seances: yearSeances)
            YearMonthlyRecapSection(seances: yearSeances, year: year)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var emptyMonthSection: some View {
        Section {
            ContentUnavailableView {
                Label("Aucune séance", systemImage: "chart.bar")
            } description: {
                Text("Aucune séance terminée pour \(month.displayLabel).")
            }
        }
    }

    @ViewBuilder
    private var emptyYearSection: some View {
        Section {
            ContentUnavailableView {
                Label("Aucune séance", systemImage: "chart.bar")
            } description: {
                Text("Aucune séance terminée pour \(year.displayLabel).")
            }
        }
    }
}

// MARK: - Scope

/// Whether the comptabilité dashboard is scoped to a single month or a year.
private enum AccountingScope: Hashable {
    case month
    case year
}

/// A segmented picker switching between the month and year views.
private struct ScopePickerSection: View {
    @Binding var mode: AccountingScope

    var body: some View {
        Section {
            Picker("Période", selection: $mode) {
                Text("Mois").tag(AccountingScope.month)
                Text("Année").tag(AccountingScope.year)
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Month selector

/// A header with previous/next month buttons around the current month label.
/// "Next" is disabled on the current real-world month.
private struct MonthSelectorSection: View {
    @Binding var month: AccountingMonth

    var body: some View {
        Section {
            HStack {
                Button {
                    month = month.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(month.displayLabel)
                    .font(.headline)
                    .foregroundStyle(.tint)

                Spacer()

                Button {
                    month = month.next()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(month.isCurrent)
            }
        }
    }
}

// MARK: - Year selector

/// A header with previous/next year buttons around the current year label.
/// "Next" is disabled on the current real-world year.
private struct YearSelectorSection: View {
    @Binding var year: AccountingYear

    var body: some View {
        Section {
            HStack {
                Button {
                    year = year.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(verbatim: year.displayLabel)
                    .font(.headline)
                    .foregroundStyle(.tint)

                Spacer()

                Button {
                    year = year.next()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(year.isCurrent)
            }
        }
    }
}

// MARK: - Export menu

/// A share menu offering CSV and PDF exports of the month's paid sessions.
private struct ExportMenu: View {
    let seances: [Seance]
    let month: AccountingMonth

    var body: some View {
        Menu {
            if let csvURL = AccountingCSVExport.writeTempFile(for: seances, month: month) {
                ShareLink(item: csvURL) {
                    Label("Exporter en CSV", systemImage: "tablecells")
                }
            }
            if let pdfURL = AccountingPDFExport.writeTempFile(for: seances, month: month) {
                ShareLink(item: pdfURL) {
                    Label("Exporter en PDF", systemImage: "doc.richtext")
                }
            }
        } label: {
            Label("Exporter", systemImage: "square.and.arrow.up")
        }
        .disabled(seances.isEmpty)
    }
}

/// A share menu offering CSV and PDF exports of the year's paid sessions.
private struct YearExportMenu: View {
    let seances: [Seance]
    let year: AccountingYear

    var body: some View {
        Menu {
            if let csvURL = AccountingCSVExport.writeTempFile(for: seances, year: year) {
                ShareLink(item: csvURL) {
                    Label("Exporter en CSV", systemImage: "tablecells")
                }
            }
            if let pdfURL = AccountingPDFExport.writeTempFile(for: seances, year: year) {
                ShareLink(item: pdfURL) {
                    Label("Exporter en PDF", systemImage: "doc.richtext")
                }
            }
        } label: {
            Label("Exporter", systemImage: "square.and.arrow.up")
        }
        .disabled(seances.isEmpty)
    }
}

// MARK: - Totals

/// Total revenue for the selected month, summed from its finished sessions.
private struct RevenueTotalsSection: View {
    let seances: [Seance]

    private var total: Double {
        seances.reduce(0) { $0 + $1.priceCHF }
    }

    var body: some View {
        Section("Revenus du mois") {
            LabeledAmountRow(title: "Total", amount: total, emphasized: true)
        }
    }
}

/// Total revenue for the selected year, summed from its finished sessions.
private struct YearTotalsSection: View {
    let seances: [Seance]

    private var total: Double {
        seances.reduce(0) { $0 + $1.priceCHF }
    }

    var body: some View {
        Section("Revenus de l'année") {
            LabeledAmountRow(title: "Total", amount: total, emphasized: true)
        }
    }
}

// MARK: - Year monthly recap

/// A 12-line recap of the year: each month with its revenue. Months without any
/// session are still listed (with a CHF 0 amount) for a complete yearly view.
private struct YearMonthlyRecapSection: View {
    let seances: [Seance]
    let year: AccountingYear

    var body: some View {
        Section("Récap par mois") {
            ForEach(year.months, id: \.fileLabel) { month in
                YearMonthRecapRow(label: month.displayLabel, amount: monthTotal(month))
            }
        }
    }

    /// Revenue of the given month within the year's sessions.
    private func monthTotal(_ month: AccountingMonth) -> Double {
        seances
            .filter { month.contains($0.date) }
            .reduce(0) { $0 + $1.priceCHF }
    }
}

/// One recap line: the month name (verbatim, already localized) and its CHF total.
private struct YearMonthRecapRow: View {
    let label: String
    let amount: Double

    var body: some View {
        HStack {
            Text(verbatim: label)
            Spacer()
            Text(verbatim: CurrencyFormat.chf(amount))
                .foregroundStyle(amount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }
}

// MARK: - Breakdown per payment method

/// Amount and count per payment method (Twint / Carte / Espèces) for the month.
private struct PaymentBreakdownSection: View {
    let seances: [Seance]

    var body: some View {
        Section("Moyen de paiement") {
            ForEach(PaymentMethod.allCases) { method in
                let stats = stats(for: method)
                PaymentMethodRow(method: method, amount: stats.amount, count: stats.count)
            }
        }
    }

    /// Total amount and number of sessions paid with `method`.
    private func stats(for method: PaymentMethod) -> (amount: Double, count: Int) {
        let matching = seances.filter { $0.paymentMethod == method.rawValue }
        let amount = matching.reduce(0) { $0 + $1.priceCHF }
        return (amount, matching.count)
    }
}

/// One payment-method line: icon, label, count and total amount.
private struct PaymentMethodRow: View {
    let method: PaymentMethod
    let amount: Double
    let count: Int

    var body: some View {
        HStack {
            Label(method.displayName, systemImage: method.icon)
                .foregroundStyle(.tint)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: CurrencyFormat.chf(amount))
                    .font(.subheadline.weight(.semibold))
                Text("\(count) payé(e)s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Month payments

/// The paid sessions of the selected month (date, client, service, price, icon).
private struct MonthPaymentsSection: View {
    let seances: [Seance]

    var body: some View {
        if !seances.isEmpty {
            Section("Séances payées") {
                ForEach(seances) { seance in
                    PaidSeanceRow(seance: seance)
                }
            }
        }
    }
}

/// One row in the paid-sessions list.
private struct PaidSeanceRow: View {
    let seance: Seance

    private var method: PaymentMethod? {
        PaymentMethod(stored: seance.paymentMethod)
    }

    var body: some View {
        HStack(spacing: 10) {
            if let method {
                Image(systemName: method.icon)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: seance.client?.name ?? String(localized: "Sans client"))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: seance.serviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(seance.date, format: .dateTime.day().month().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: CurrencyFormat.chf(seance.priceCHF))
                .font(.subheadline)
                .foregroundStyle(.tint)
        }
    }
}

// MARK: - Shared pieces

/// A title on the left and a CHF amount on the right.
private struct LabeledAmountRow: View {
    let title: LocalizedStringKey
    let amount: Double
    var emphasized: Bool = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: CurrencyFormat.chf(amount))
                .font(emphasized ? .headline : .body)
                .foregroundStyle(emphasized ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
    }
}

#Preview {
    NavigationStack { ComptabiliteView() }
        .modelContainer(for: [Client.self, Seance.self], inMemory: true)
}
