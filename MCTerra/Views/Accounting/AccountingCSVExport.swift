//
//  AccountingCSVExport.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Builds a CSV of the paid sessions for a month, ready to share via `ShareLink`.
///
/// Format targets Excel FR/CH: UTF-8 (with BOM so accents render), `;` separator
/// and `,` decimals. Columns: Date, Client, Forfait, Durée, Prix CHF, Paiement.
enum AccountingCSVExport {
    /// Produces the CSV string for `seances` (assumed already filtered to the month).
    static func makeCSV(for seances: [Seance]) -> String {
        let header = ["Date", "Client", "Forfait", "Durée (min)", "Prix CHF", "Paiement"]
        var rows = [header.map(escape).joined(separator: ";")]

        for seance in seances {
            let row = [
                Self.dateFormatter.string(from: seance.date),
                seance.client?.name ?? "Sans client",
                seance.serviceName,
                String(seance.durationMinutes),
                priceField(seance.priceCHF),
                paymentLabel(seance.paymentMethod),
            ]
            rows.append(row.map(escape).joined(separator: ";"))
        }

        // Total line for quick reconciliation in the spreadsheet.
        let total = seances.reduce(0) { $0 + $1.priceCHF }
        let totalRow = ["", "", "", "Total", priceField(total), ""]
        rows.append(totalRow.map(escape).joined(separator: ";"))

        return rows.joined(separator: "\r\n")
    }

    /// Writes the CSV to a temp file and returns its URL (so `ShareLink` can ship a
    /// nicely named file). A UTF-8 BOM is prepended so Excel keeps the accents.
    static func writeTempFile(for seances: [Seance], month: AccountingMonth) -> URL? {
        let csv = makeCSV(for: seances)
        let bom = "\u{FEFF}"
        guard let data = (bom + csv).data(using: .utf8) else { return nil }

        let name = "MC-TERRA_Comptabilite_\(month.fileLabel).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Yearly export

    /// Produces a yearly CSV for `seances` (assumed already filtered to the year):
    /// one line per month with its revenue and session count, a yearly total, then
    /// a payment-method breakdown block. Targets a tax-friendly, readable layout.
    static func makeYearCSV(for seances: [Seance], year: AccountingYear) -> String {
        let calendar = Calendar.current
        var rows: [String] = []

        // Monthly recap block.
        let monthHeader = ["Mois", "Séances", "CA CHF"]
        rows.append(monthHeader.map(escape).joined(separator: ";"))

        for month in year.months {
            let monthSeances = seances.filter { month.contains($0.date, calendar: calendar) }
            let amount = monthSeances.reduce(0) { $0 + $1.priceCHF }
            let row = [
                month.displayLabel,
                String(monthSeances.count),
                priceField(amount),
            ]
            rows.append(row.map(escape).joined(separator: ";"))
        }

        // Yearly total line.
        let total = seances.reduce(0) { $0 + $1.priceCHF }
        let totalRow = ["Total", String(seances.count), priceField(total)]
        rows.append(totalRow.map(escape).joined(separator: ";"))

        // Empty separator line, then the payment breakdown block.
        rows.append("")
        let paymentHeader = ["Moyen de paiement", "Séances", "CA CHF"]
        rows.append(paymentHeader.map(escape).joined(separator: ";"))

        for method in PaymentMethod.allCases {
            let matching = seances.filter { $0.paymentMethod == method.rawValue }
            guard !matching.isEmpty else { continue }
            let amount = matching.reduce(0) { $0 + $1.priceCHF }
            let row = [
                paymentLabel(method.rawValue),
                String(matching.count),
                priceField(amount),
            ]
            rows.append(row.map(escape).joined(separator: ";"))
        }

        return rows.joined(separator: "\r\n")
    }

    /// Writes the yearly CSV to a temp file and returns its URL. A UTF-8 BOM is
    /// prepended so Excel keeps the accents.
    static func writeTempFile(for seances: [Seance], year: AccountingYear) -> URL? {
        let csv = makeYearCSV(for: seances, year: year)
        let bom = "\u{FEFF}"
        guard let data = (bom + csv).data(using: .utf8) else { return nil }

        let name = "MC-TERRA_Comptabilite_\(year.fileLabel).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    /// French-style decimal (comma) with at most two decimals, e.g. "120" / "89,95".
    private static func priceField(_ amount: Double) -> String {
        var formatter = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .grouping(.never)
        formatter.locale = Locale(identifier: "fr_CH")
        return amount.formatted(formatter)
    }

    /// Human label for a stored payment method ("Non payé" when empty).
    private static func paymentLabel(_ stored: String) -> String {
        switch PaymentMethod(stored: stored) {
        case .twint: return "Twint"
        case .card: return "Carte"
        case .cash: return "Espèces"
        case nil: return "Non payé"
        }
    }

    /// Escapes a CSV field: wraps in quotes and doubles inner quotes when the value
    /// contains a separator, quote or newline.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
