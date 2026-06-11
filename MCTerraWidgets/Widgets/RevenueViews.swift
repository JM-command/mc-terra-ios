//
//  RevenueViews.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Per-size layouts for the "Revenus du mois" widget. Split into small structs
//  so each body stays cheap for the Swift type-checker. French labels are
//  hard-coded (PT pass comes later).

import SwiftUI
import WidgetKit

// MARK: - Month title helper

private func currentMonthName() -> String {
    Date.now.formatted(.dateTime.month(.wide)).capitalized
}

/// Payment-method display metadata, mirrored from the app enum without depending
/// on the app-only `PaymentMethod` type.
private func methodLabel(_ raw: String) -> String {
    switch raw {
    case "twint": return "Twint"
    case "carte": return "Carte"
    case "cash": return "Espèces"
    default: return "Autre"
    }
}

private func methodIcon(_ raw: String) -> String {
    switch raw {
    case "twint": return "francsign.circle"
    case "carte": return "creditcard"
    case "cash": return "banknote"
    default: return "questionmark.circle"
    }
}

// MARK: - Small: just the total

struct RevenueSmall: View {
    let entry: RevenueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(currentMonthName())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("CHF")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(WidgetFormat.chf(entry.total))
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("\(entry.count) séance\(entry.count > 1 ? "s" : "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium: total + count + breakdown

struct RevenueMedium: View {
    let entry: RevenueEntry

    /// Methods that actually have revenue, ordered twint → carte → cash → autre.
    private var orderedMethods: [(String, Double)] {
        let order = ["twint", "carte", "cash", ""]
        return order.compactMap { key in
            guard let v = entry.byMethod[key], v > 0 else { return nil }
            return (key, v)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentMonthName())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Text("CHF \(WidgetFormat.chf(entry.total))")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(entry.count) séance\(entry.count > 1 ? "s" : "") terminée\(entry.count > 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if orderedMethods.isEmpty {
                    Text("Aucun encaissement")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedMethods, id: \.0) { method, amount in
                        Label {
                            HStack {
                                Text(methodLabel(method))
                                    .font(.caption2)
                                Spacer(minLength: 4)
                                Text(WidgetFormat.chf(amount))
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                            }
                        } icon: {
                            Image(systemName: methodIcon(method))
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large: total + recent paid sessions

struct RevenueLarge: View {
    let entry: RevenueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentMonthName())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text("CHF \(WidgetFormat.chf(entry.total))")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(entry.count) séance\(entry.count > 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if entry.recent.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "francsign.circle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        Text("Aucune séance payée ce mois")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.recent.prefix(5)) { session in
                    PaidRow(session: session)
                    if session.id != entry.recent.prefix(5).last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Paid session row

private struct PaidRow: View {
    let session: SessionSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: methodIcon(session.paymentMethod))
                .font(.callout)
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.clientName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(WidgetFormat.dateTime(session.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("CHF \(WidgetFormat.chf(session.priceCHF))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}
