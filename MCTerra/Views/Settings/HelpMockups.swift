//
//  HelpMockups.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

// Static, non-interactive mockups that imitate the real bits of UI.
// They reuse the same styles as the app (gray capsule, .tint, SF Symbols)
// so Marta recognizes exactly what to tap, without needing screenshots.
// Every mockup disables hit testing: they are pictures, not real controls.

/// Fake input bar, identical to ContentView's `inputBar` (capsule, +, "Message", blue mic).
struct MockInputBar: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.title3)

            Text("Message")
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.gray.opacity(0.15)))
        .allowsHitTesting(false)
    }
}

/// Fake menu row, identical to MenuView's rows (Label + .tint tint).
struct MockMenuRow: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
            )
            .allowsHitTesting(false)
    }
}

/// Fake text field, imitating NewClientView's "Nom" field inside a Form row.
struct MockTextField: View {
    let placeholder: LocalizedStringKey

    var body: some View {
        Text(placeholder)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
            )
            .allowsHitTesting(false)
    }
}

/// Fake "Enregistrer" confirmation button, imitating the toolbar action.
struct MockSaveButton: View {
    var body: some View {
        Text("Enregistrer")
            .font(.headline)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
    }
}

/// Fake segmented Picker, imitating the Réglages "Thème" / "Langue" pickers.
struct MockPicker: View {
    let options: [LocalizedStringKey]
    /// Index of the option drawn as selected.
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                segment(option, isSelected: index == selectedIndex)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
        .allowsHitTesting(false)
    }

    // Extracted into its own function to keep the type-checker fast.
    @ViewBuilder
    private func segment(_ option: LocalizedStringKey, isSelected: Bool) -> some View {
        Text(option)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background {
                if isSelected {
                    // Selected segment looks lifted, like a real UISegmentedControl.
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.background)
                        .shadow(radius: 1, y: 1)
                }
            }
    }
}

/// Fake hamburger (☰) button, imitating ContentView's header menu button.
struct MockHamburgerButton: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.title2)
            .foregroundStyle(.primary)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
            )
            .allowsHitTesting(false)
    }
}

/// Fake "Accueil" floating button, imitating MenuView's home button.
struct MockHomeButton: View {
    var body: some View {
        Label("Accueil", systemImage: "house")
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.gray.opacity(0.15)))
            .foregroundStyle(.primary)
            .allowsHitTesting(false)
    }
}

// MARK: - Form rows (séances)

/// Generic fake "Form" row: a left label and a tinted value on the right,
/// imitating a row inside a grouped Form (e.g. the "Forfait"/"Durée" lines).
/// Used by the "Créer et gérer une séance" article.
struct MockFormRow: View {
    let title: LocalizedStringKey
    /// Verbatim value (brand service names / formatted durations aren't localized).
    let value: String
    /// Optional SF Symbol drawn before the value (e.g. the location icon).
    var valueIcon: String?

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 6) {
                if let valueIcon {
                    Image(systemName: valueIcon)
                }
                Text(verbatim: value)
            }
            .foregroundStyle(.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
        .allowsHitTesting(false)
    }
}

/// Fake "Lieu" Form row reusing the real `SessionLocation` label + icon, so the
/// location stays correctly localized (Cabinet → Consultório in PT).
struct MockLocationRow: View {
    let location: SessionLocation

    var body: some View {
        HStack {
            Text("Lieu")
                .foregroundStyle(.primary)
            Spacer()
            Label(location.displayName, systemImage: location.icon)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Start / Stop buttons (live session)

/// Fake Play / Stop buttons, imitating SeanceDetailView's "Démarrer" (blue,
/// play.circle.fill) and "Terminer" (red, stop.circle.fill) buttons.
/// Used by the "Démarrer et terminer une séance" article.
struct MockStartStopButtons: View {
    var body: some View {
        VStack(spacing: 12) {
            mockButton(
                title: "Démarrer la séance",
                systemImage: "play.circle.fill",
                tint: AnyShapeStyle(.tint)
            )
            mockButton(
                title: "Terminer la séance",
                systemImage: "stop.circle.fill",
                tint: AnyShapeStyle(.red)
            )
        }
        .allowsHitTesting(false)
    }

    // Extracted to keep the type-checker fast.
    @ViewBuilder
    private func mockButton(
        title: LocalizedStringKey,
        systemImage: String,
        tint: AnyShapeStyle
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
            )
    }
}

// MARK: - Payment selector

/// Fake segmented payment picker, imitating SeanceSummaryEditorView's
/// "Twint / Carte / Espèces" segmented control (with their SF Symbols).
/// Used by the "Noter le paiement" article.
struct MockPaymentSelector: View {
    /// Index of the segment drawn as selected.
    let selectedIndex: Int

    private let options: [(LocalizedStringKey, String)] = [
        ("Twint", "francsign.circle"),
        ("Carte", "creditcard"),
        ("Espèces", "banknote")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                segment(option.0, icon: option.1, isSelected: index == selectedIndex)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
        .allowsHitTesting(false)
    }

    // Extracted to keep the type-checker fast.
    @ViewBuilder
    private func segment(_ label: LocalizedStringKey, icon: String, isSelected: Bool) -> some View {
        Label(label, systemImage: icon)
            .font(.footnote)
            .lineLimit(1)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.background)
                        .shadow(radius: 1, y: 1)
                }
            }
    }
}

// MARK: - Agenda day cell

/// Fake month-grid day cell, imitating AgendaView's `DayCell`: a day number
/// then a few colored event pills. Used by the "Voir l'agenda" article.
struct MockAgendaDayCell: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: "12")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.tint))

            VStack(spacing: 3) {
                pill("Marta", color: Color(red: 0.10, green: 0.65, blue: 0.62))
                pill("Sofia", color: Color(red: 0.45, green: 0.35, blue: 0.80))
                pill("João", color: Color(red: 0.90, green: 0.60, blue: 0.25))
            }
        }
        .padding(10)
        .frame(width: 110)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
        .allowsHitTesting(false)
    }

    // One colored event pill, like AgendaView's `EventPill`.
    @ViewBuilder
    private func pill(_ label: String, color: Color) -> some View {
        Text(verbatim: label)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color))
    }
}

// MARK: - Revenue total + export buttons

/// Fake revenue total ("1 240 CHF") plus CSV / PDF export buttons, imitating
/// the Comptabilité screen. Used by the "Voir les revenus" article.
struct MockRevenueExport: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Total")
                    .foregroundStyle(.primary)
                Spacer()
                Text(verbatim: "1 240 CHF")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
            )

            HStack(spacing: 12) {
                exportButton(title: "Exporter en CSV", systemImage: "tablecells")
                exportButton(title: "Exporter en PDF", systemImage: "doc.richtext")
            }
        }
        .allowsHitTesting(false)
    }

    // One bordered export button, like the ShareLink rows in the export menu.
    @ViewBuilder
    private func exportButton(title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.tint, lineWidth: 1)
            )
    }
}
