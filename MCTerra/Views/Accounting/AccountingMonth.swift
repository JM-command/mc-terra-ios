//
//  AccountingMonth.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftUI

/// A single calendar month (year + month) used to scope the accounting view and
/// its CSV/PDF exports. Comparable so previous/next navigation is trivial.
struct AccountingMonth: Equatable, Comparable {
    let year: Int
    let month: Int

    /// The month containing `date`, in the current calendar.
    init(containing date: Date, calendar: Calendar = .current) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        self.year = comps.year ?? 2026
        self.month = comps.month ?? 1
    }

    private init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The first instant of this month, used as an anchor for formatting/filtering.
    func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    /// The month before this one.
    func previous(calendar: Calendar = .current) -> AccountingMonth {
        let date = calendar.date(byAdding: .month, value: -1, to: startDate(calendar: calendar)) ?? .now
        return AccountingMonth(containing: date, calendar: calendar)
    }

    /// The month after this one.
    func next(calendar: Calendar = .current) -> AccountingMonth {
        let date = calendar.date(byAdding: .month, value: 1, to: startDate(calendar: calendar)) ?? .now
        return AccountingMonth(containing: date, calendar: calendar)
    }

    /// True when this month is the current real-world month (next disabled then).
    var isCurrent: Bool {
        self == AccountingMonth(containing: .now)
    }

    /// True when `date` falls inside this month.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: startDate(calendar: calendar), toGranularity: .month)
    }

    /// Localized label like "Juin 2026" (capitalized), for the header/picker.
    var displayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.dateFormat = "LLLL yyyy"
        let label = formatter.string(from: startDate())
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Compact label like "2026-06", used in export filenames.
    var fileLabel: String {
        String(format: "%04d-%02d", year, month)
    }

    static func < (lhs: AccountingMonth, rhs: AccountingMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// A single calendar year used to scope the yearly accounting view and its
/// CSV/PDF exports. Mirrors `AccountingMonth` so previous/next navigation works
/// the same way.
struct AccountingYear: Equatable, Comparable {
    let year: Int

    /// The year containing `date`, in the current calendar.
    init(containing date: Date, calendar: Calendar = .current) {
        let comps = calendar.dateComponents([.year], from: date)
        self.year = comps.year ?? 2026
    }

    private init(year: Int) {
        self.year = year
    }

    /// The year before this one.
    func previous() -> AccountingYear {
        AccountingYear(year: year - 1)
    }

    /// The year after this one.
    func next() -> AccountingYear {
        AccountingYear(year: year + 1)
    }

    /// True when this year is the current real-world year (next disabled then).
    var isCurrent: Bool {
        self == AccountingYear(containing: .now)
    }

    /// True when `date` falls inside this year.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.year, from: date) == year
    }

    /// The twelve months of this year, ordered January to December.
    var months: [AccountingMonth] {
        (1...12).map { AccountingMonth(containing: monthStart($0)) }
    }

    /// First instant of `month` (1...12) within this year.
    private func monthStart(_ month: Int, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    /// Label like "2026", for the header/picker.
    var displayLabel: String {
        String(year)
    }

    /// Compact label like "2026", used in export filenames.
    var fileLabel: String {
        String(format: "%04d", year)
    }

    static func < (lhs: AccountingYear, rhs: AccountingYear) -> Bool {
        lhs.year < rhs.year
    }
}

/// Formats CHF amounts the Swiss way: thousands grouped with a space and no
/// decimals when whole, e.g. "120 CHF" / "1 240 CHF" / "89.95 CHF".
enum CurrencyFormat {
    static func chf(_ amount: Double) -> String {
        var formatter = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .grouping(.automatic)
        formatter.locale = Locale(identifier: "fr_CH")
        return "\(amount.formatted(formatter)) CHF"
    }
}

/// MC-TERRA brand colors, mirrored from the website export templates so the
/// in-app PDF matches the look of the site-generated documents.
enum BrandColor {
    /// Teal accent (#4DB8B0).
    static let accent = Color(red: 0x4D / 255, green: 0xB8 / 255, blue: 0xB0 / 255)
    /// Deep violet used for section titles (#634B77).
    static let violet = Color(red: 0x63 / 255, green: 0x4B / 255, blue: 0x77 / 255)
    /// Warm near-black body text (#2A2520).
    static let text = Color(red: 0x2A / 255, green: 0x25 / 255, blue: 0x20 / 255)
    /// Muted grey (#6B7280).
    static let muted = Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
    /// Light row background (#F9FAFB).
    static let surface = Color(red: 0xF9 / 255, green: 0xFA / 255, blue: 0xFB / 255)
    /// Hairline border (#E5E7EB).
    static let border = Color(red: 0xE5 / 255, green: 0xE7 / 255, blue: 0xEB / 255)
}

/// Business identity printed on every export, mirrored from the website footer.
enum BrandIdentity {
    static let name = "MC-TERRA"
    static let owner = "Marta Coelho"
    static let address = "Route de Gilly 30, 1180 Rolle, Suisse"
    static let contact = "contact@mc-terra.ch • mc-terra.ch"
    static let vatNotice = "Non assujettie à la TVA"
    static let tagline = "Marta Coelho · Coaching & Accompagnement"
}
