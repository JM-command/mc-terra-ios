//
//  AccountingPDFExport.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import UIKit

/// Builds a one-page, A4 PDF recap of a month's paid sessions, branded like the
/// website's "Récapitulatif comptable" template (MC-TERRA teal header, violet
/// section titles, payment breakdown, a sessions table and a muted footer).
///
/// The visual layout lives in `AccountingReportDocument` (a SwiftUI view) and is
/// rasterised to PDF through `ImageRenderer`, so the in-app document stays in
/// sync with the SwiftUI styling used elsewhere in the app.
enum AccountingPDFExport {
    /// A4 size in points (72 dpi): 595 x 842.
    private static let pageSize = CGSize(width: 595, height: 842)

    /// Renders the report and writes it to a temp file, returning its URL so
    /// `ShareLink` can ship a nicely named document. Returns `nil` on failure.
    @MainActor
    static func writeTempFile(
        for seances: [Seance],
        month: AccountingMonth
    ) -> URL? {
        let document = AccountingReportDocument(seances: seances, month: month)
            .frame(width: pageSize.width)

        let renderer = ImageRenderer(content: document)
        renderer.proposedSize = .init(width: pageSize.width, height: nil)

        let name = "MC-TERRA_Comptabilite_\(month.fileLabel).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        var success = false
        renderer.render { _, context in
            // Real A4 portrait page. If a long month overflows A4, the page grows to
            // fit instead of clipping.
            let contentHeight = renderer.uiImage?.size.height ?? pageSize.height
            let pageHeight = max(pageSize.height, contentHeight)
            var box = CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: pageHeight))

            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            // PDF coordinates have their origin bottom-left, so the rendered content
            // would sit at the BOTTOM of the page. Push it up by the leftover space
            // so it sits at the TOP, like a normal document.
            pdf.translateBy(x: 0, y: pageHeight - contentHeight)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            success = true
        }

        return success ? url : nil
    }

    /// Renders the yearly report and writes it to a temp file, returning its URL.
    /// Returns `nil` on failure.
    @MainActor
    static func writeTempFile(
        for seances: [Seance],
        year: AccountingYear
    ) -> URL? {
        let document = AccountingYearReportDocument(seances: seances, year: year)
            .frame(width: pageSize.width)

        let renderer = ImageRenderer(content: document)
        renderer.proposedSize = .init(width: pageSize.width, height: nil)

        let name = "MC-TERRA_Comptabilite_\(year.fileLabel).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        var success = false
        renderer.render { _, context in
            let contentHeight = renderer.uiImage?.size.height ?? pageSize.height
            let pageHeight = max(pageSize.height, contentHeight)
            var box = CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: pageHeight))

            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: pageHeight - contentHeight)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            success = true
        }

        return success ? url : nil
    }
}

// MARK: - Report document (rasterised to PDF)

/// The printable page. Pure SwiftUI so it mirrors the brand colours defined in
/// `BrandColor` / `BrandIdentity`, matching the website's PDF templates.
private struct AccountingReportDocument: View {
    let seances: [Seance]
    let month: AccountingMonth

    private var total: Double {
        seances.reduce(0) { $0 + $1.priceCHF }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            summaryBox
            paymentBreakdown
            sessionsTable
            Spacer(minLength: 24)
            legalAndFooter
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(BrandIdentity.name)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.accent)
            Text("Récapitulatif comptable")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.text)
            Text(month.displayLabel)
                .font(.system(size: 10))
                .foregroundStyle(BrandColor.muted)

            VStack(alignment: .leading, spacing: 1) {
                Text(BrandIdentity.owner)
                Text(BrandIdentity.address)
                Text(BrandIdentity.contact)
                Text(BrandIdentity.vatNotice)
            }
            .font(.system(size: 9))
            .foregroundStyle(BrandColor.muted)
            .padding(.top, 8)
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandColor.accent)
                .frame(height: 2)
        }
        .padding(.bottom, 22)
    }

    // MARK: Summary

    private var summaryBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Résumé")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.violet)
                .padding(.bottom, 2)

            summaryRow("Chiffre d'affaires", value: CurrencyFormat.chf(total), accent: true)
            summaryRow("Séances payées", value: "\(seances.count)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.bottom, 18)
    }

    private func summaryRow(_ label: String, value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(BrandColor.text)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent ? BrandColor.accent : BrandColor.text)
        }
    }

    // MARK: Payment breakdown

    /// Total + count per payment method, only listing methods actually used.
    private var paymentBreakdown: some View {
        let rows = PaymentMethod.allCases.compactMap { method -> (PaymentMethod, Double, Int)? in
            let matching = seances.filter { $0.paymentMethod == method.rawValue }
            guard !matching.isEmpty else { return nil }
            return (method, matching.reduce(0) { $0 + $1.priceCHF }, matching.count)
        }

        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Répartition par moyen de paiement")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(BrandColor.violet)

                    ForEach(rows, id: \.0) { method, amount, count in
                        HStack {
                            Text(methodLabel(method))
                                .font(.system(size: 10))
                                .foregroundStyle(BrandColor.text)
                            Spacer()
                            Text("\(count) séance(s)")
                                .font(.system(size: 9))
                                .foregroundStyle(BrandColor.muted)
                            Text(CurrencyFormat.chf(amount))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(BrandColor.text)
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: Sessions table

    private var sessionsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Détail des séances")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.violet)
                .padding(.bottom, 8)

            // Header row, teal underline like the site tables.
            tableRow(
                date: "Date", client: "Client", service: "Forfait",
                duration: "Durée", price: "Prix", payment: "Paiement",
                isHeader: true
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(BrandColor.accent).frame(height: 2)
            }

            ForEach(seances) { seance in
                tableRow(
                    date: Self.dateFormatter.string(from: seance.date),
                    client: seance.client?.name ?? "Sans client",
                    service: seance.serviceName,
                    duration: "\(seance.durationMinutes) min",
                    price: CurrencyFormat.chf(seance.priceCHF),
                    payment: methodLabel(PaymentMethod(stored: seance.paymentMethod)),
                    isHeader: false
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(BrandColor.border).frame(height: 1)
                }
            }
        }
    }

    private func tableRow(
        date: String, client: String, service: String,
        duration: String, price: String, payment: String,
        isHeader: Bool
    ) -> some View {
        let weight: Font.Weight = isHeader ? .bold : .regular
        let color = isHeader ? BrandColor.accent : BrandColor.text

        return HStack(spacing: 4) {
            cell(date, width: 70, weight: weight, color: color)
            // Client and Forfait share the flexible remaining width equally.
            cell(client, weight: weight, color: color)
            cell(service, weight: weight, color: color)
            cell(duration, width: 55, weight: weight, color: color)
            cell(price, width: 70, align: .trailing, weight: weight, color: color)
            cell(payment, width: 70, align: .trailing, weight: weight, color: color)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func cell(
        _ text: String, width: CGFloat? = nil,
        align: Alignment = .leading, weight: Font.Weight, color: Color
    ) -> some View {
        let view = Text(text)
            .font(.system(size: 8, weight: weight))
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(align == .trailing ? .trailing : .leading)

        if let width {
            view.frame(width: width, alignment: align)
        } else {
            view.frame(maxWidth: .infinity, alignment: align)
        }
    }

    // MARK: Legal + footer

    private var legalAndFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MC-TERRA · Entreprise individuelle · \(BrandIdentity.vatNotice)")
                .font(.system(size: 9))
                .foregroundStyle(BrandColor.muted)
            Text("Document généré le \(Self.longDateFormatter.string(from: .now))")
                .font(.system(size: 9))
                .foregroundStyle(BrandColor.muted)

            Divider().background(BrandColor.border).padding(.top, 10)
            HStack {
                Text("mc-terra.ch")
                Spacer()
                Text(BrandIdentity.tagline)
            }
            .font(.system(size: 7))
            .foregroundStyle(BrandColor.muted)
            .padding(.top, 8)
        }
    }

    // MARK: Helpers

    private func methodLabel(_ method: PaymentMethod?) -> String {
        switch method {
        case .twint: return "Twint"
        case .card: return "Carte"
        case .cash: return "Espèces"
        case nil: return "Non payé"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.dateStyle = .long
        return formatter
    }()
}

// MARK: - Yearly report document (rasterised to PDF)

/// The printable yearly page. Same brand styling as the monthly report, but the
/// table lists revenue per month (12 rows) with a yearly total, plus the yearly
/// payment-method breakdown. Targets a readable layout for a tax declaration.
private struct AccountingYearReportDocument: View {
    let seances: [Seance]
    let year: AccountingYear

    private var total: Double {
        seances.reduce(0) { $0 + $1.priceCHF }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YearReportHeader(year: year)
            YearReportSummary(total: total, count: seances.count)
            YearReportPaymentBreakdown(seances: seances)
            YearReportMonthlyTable(seances: seances, year: year, total: total)
            Spacer(minLength: 24)
            YearReportFooter()
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: Header

private struct YearReportHeader: View {
    let year: AccountingYear

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(BrandIdentity.name)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.accent)
            Text("Récapitulatif comptable annuel")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.text)
            Text(year.displayLabel)
                .font(.system(size: 10))
                .foregroundStyle(BrandColor.muted)

            VStack(alignment: .leading, spacing: 1) {
                Text(BrandIdentity.owner)
                Text(BrandIdentity.address)
                Text(BrandIdentity.contact)
                Text(BrandIdentity.vatNotice)
            }
            .font(.system(size: 9))
            .foregroundStyle(BrandColor.muted)
            .padding(.top, 8)
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandColor.accent)
                .frame(height: 2)
        }
        .padding(.bottom, 22)
    }
}

// MARK: Summary

private struct YearReportSummary: View {
    let total: Double
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Résumé")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.violet)
                .padding(.bottom, 2)

            summaryRow("Chiffre d'affaires annuel", value: CurrencyFormat.chf(total), accent: true)
            summaryRow("Séances payées", value: "\(count)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.bottom, 18)
    }

    private func summaryRow(_ label: String, value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(BrandColor.text)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent ? BrandColor.accent : BrandColor.text)
        }
    }
}

// MARK: Payment breakdown

private struct YearReportPaymentBreakdown: View {
    let seances: [Seance]

    var body: some View {
        let rows = PaymentMethod.allCases.compactMap { method -> (PaymentMethod, Double, Int)? in
            let matching = seances.filter { $0.paymentMethod == method.rawValue }
            guard !matching.isEmpty else { return nil }
            return (method, matching.reduce(0) { $0 + $1.priceCHF }, matching.count)
        }

        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Répartition par moyen de paiement")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(BrandColor.violet)

                    ForEach(rows, id: \.0) { method, amount, count in
                        HStack {
                            Text(AccountingPaymentLabel.label(for: method))
                                .font(.system(size: 10))
                                .foregroundStyle(BrandColor.text)
                            Spacer()
                            Text("\(count) séance(s)")
                                .font(.system(size: 9))
                                .foregroundStyle(BrandColor.muted)
                            Text(CurrencyFormat.chf(amount))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(BrandColor.text)
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }
}

// MARK: Monthly table

private struct YearReportMonthlyTable: View {
    let seances: [Seance]
    let year: AccountingYear
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Détail par mois")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(BrandColor.violet)
                .padding(.bottom, 8)

            // Header row, teal underline like the site tables.
            YearTableRow(month: "Mois", count: "Séances", revenue: "CA", isHeader: true)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(BrandColor.accent).frame(height: 2)
                }

            ForEach(year.months, id: \.fileLabel) { month in
                let monthSeances = seances.filter { month.contains($0.date) }
                let amount = monthSeances.reduce(0) { $0 + $1.priceCHF }
                YearTableRow(
                    month: month.displayLabel,
                    count: "\(monthSeances.count)",
                    revenue: CurrencyFormat.chf(amount),
                    isHeader: false
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(BrandColor.border).frame(height: 1)
                }
            }

            // Yearly total row, emphasized.
            YearTableRow(
                month: "Total",
                count: "\(seances.count)",
                revenue: CurrencyFormat.chf(total),
                isHeader: true
            )
            .padding(.top, 2)
        }
    }
}

private struct YearTableRow: View {
    let month: String
    let count: String
    let revenue: String
    let isHeader: Bool

    var body: some View {
        let weight: Font.Weight = isHeader ? .bold : .regular
        let color = isHeader ? BrandColor.accent : BrandColor.text

        return HStack(spacing: 4) {
            Text(month)
                .font(.system(size: 9, weight: weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(count)
                .font(.system(size: 9, weight: weight))
                .foregroundStyle(color)
                .frame(width: 70, alignment: .trailing)
            Text(revenue)
                .font(.system(size: 9, weight: weight))
                .foregroundStyle(color)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

// MARK: Footer

private struct YearReportFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MC-TERRA · Entreprise individuelle · \(BrandIdentity.vatNotice)")
                .font(.system(size: 9))
                .foregroundStyle(BrandColor.muted)
            Text("Document généré le \(Self.longDateFormatter.string(from: .now))")
                .font(.system(size: 9))
                .foregroundStyle(BrandColor.muted)

            Divider().background(BrandColor.border).padding(.top, 10)
            HStack {
                Text("mc-terra.ch")
                Spacer()
                Text(BrandIdentity.tagline)
            }
            .font(.system(size: 7))
            .foregroundStyle(BrandColor.muted)
            .padding(.top, 8)
        }
    }

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.dateStyle = .long
        return formatter
    }()
}

// MARK: - Shared payment label

/// Plain-string label for a payment method, shared by the report documents.
private enum AccountingPaymentLabel {
    static func label(for method: PaymentMethod?) -> String {
        switch method {
        case .twint: return "Twint"
        case .card: return "Carte"
        case .cash: return "Espèces"
        case nil: return "Non payé"
        }
    }
}
