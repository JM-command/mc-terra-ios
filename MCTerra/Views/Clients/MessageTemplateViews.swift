//
//  MessageTemplateViews.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

// MARK: - Row

/// A single row in the "Messages prêts" section: an icon + the template title.
///
/// Tapping it runs `action` (open WhatsApp directly, or present a form sheet first,
/// depending on the template). Disabled and dimmed when the client has no phone.
struct MessageTemplateRow: View {
    let template: MessageTemplate
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(template.title)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
            } icon: {
                Image(systemName: template.icon)
                    .foregroundStyle(.tint)
            }
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Form sheet

/// A small form shown before sending templates that need extra input
/// (reconnect → number + unit pickers, retreat → retreat picker).
///
/// The user picks values, then taps "Ouvrir dans WhatsApp": we encode the picked
/// values, resolve them into substitution tokens, build the message body in the
/// *client's* language, and open the `wa.me` link with the text pre-filled.
struct MessageTemplateFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let client: Client
    let template: MessageTemplate

    /// Free-text value (used only by `.text` fields).
    @State private var textValue: String
    /// Picked count (used only by `.number` fields).
    @State private var numberValue: Int
    /// Picked unit raw value (used only by `.number` fields).
    @State private var unitValue: String
    /// Picked option raw value (used only by `.options` fields).
    @State private var optionValue: String

    init(client: Client, template: MessageTemplate) {
        self.client = client
        self.template = template

        // Seed each state from the field's default, decoding the number field's
        // "<count>|<unit>" encoding where applicable.
        let field = template.field
        let raw = field?.defaultValue ?? ""

        switch field?.kind {
        case .number(let range, _):
            let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
            let count = parts.first.flatMap { Int($0) } ?? range.lowerBound
            _numberValue = State(initialValue: range.contains(count) ? count : range.lowerBound)
            _unitValue = State(initialValue: parts.count > 1 ? parts[1] : DurationUnit.days.rawValue)
            _textValue = State(initialValue: "")
            _optionValue = State(initialValue: "")
        case .options(let options):
            _optionValue = State(initialValue: raw.isEmpty ? (options.first?.value ?? "") : raw)
            _textValue = State(initialValue: "")
            _numberValue = State(initialValue: 1)
            _unitValue = State(initialValue: DurationUnit.days.rawValue)
        default: // .text or no field
            _textValue = State(initialValue: raw)
            _numberValue = State(initialValue: 1)
            _unitValue = State(initialValue: DurationUnit.days.rawValue)
            _optionValue = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let field = template.field {
                    MessageTemplateFieldSection(
                        field: field,
                        textValue: $textValue,
                        numberValue: $numberValue,
                        unitValue: $unitValue,
                        optionValue: $optionValue
                    )
                }
                previewSection
            }
            .navigationTitle(template.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ouvrir dans WhatsApp", action: send)
                        .disabled(!isValid)
                }
            }
        }
    }

    // MARK: Preview of the message that will be sent

    @ViewBuilder
    private var previewSection: some View {
        Section("Aperçu") {
            Text(verbatim: resolvedBody)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Logic

    /// The raw value passed to `field.resolve`, encoded per field kind.
    /// Number fields are encoded as `"<count>|<unit>"`; others pass their value directly.
    private var rawInput: String {
        switch template.field?.kind {
        case .number:
            return "\(numberValue)|\(unitValue)"
        case .options:
            return optionValue
        case .text:
            return textValue
        case .none:
            return ""
        }
    }

    /// Whether the current input is complete enough to send.
    private var isValid: Bool {
        switch template.field?.kind {
        case .text:
            return !textValue.trimmingCharacters(in: .whitespaces).isEmpty
        case .options:
            return !optionValue.isEmpty
        case .number, .none:
            return true
        }
    }

    /// Substitution tokens resolved from the current input.
    private var resolvedValues: [String: String] {
        guard let field = template.field else { return [:] }
        return field.resolve(rawInput, client)
    }

    /// The final message body, in the client's language.
    private var resolvedBody: String {
        template.body(for: client, values: resolvedValues)
    }

    /// Build the wa.me URL with the pre-filled text and hand it to the system.
    private func send() {
        guard let url = MessageTemplate.whatsAppURL(
            phone: client.phone,
            body: resolvedBody
        ) else { return }
        openURL(url)
        dismiss()
    }
}

// MARK: - Field section (renders the right control per field kind)

/// Renders the input control(s) for a single `MessageTemplateField`, choosing the
/// presentation from its `kind`: a text field, a number + unit picker pair, or an
/// options picker. Bindings are owned by the parent `MessageTemplateFormSheet`.
private struct MessageTemplateFieldSection: View {
    let field: MessageTemplateField

    @Binding var textValue: String
    @Binding var numberValue: Int
    @Binding var unitValue: String
    @Binding var optionValue: String

    var body: some View {
        Section {
            switch field.kind {
            case .text:
                TextField(field.prompt, text: $textValue)
            case .number(let range, let units):
                numberPickers(range: range, units: units)
            case .options(let options):
                optionsPicker(options)
            }
        } header: {
            Text(field.prompt)
        }
    }

    // A count picker (menu) + a unit picker (menu), side by side as labelled rows.
    @ViewBuilder
    private func numberPickers(range: ClosedRange<Int>, units: [MessageTemplateOption]) -> some View {
        Picker("Nombre", selection: $numberValue) {
            ForEach(Array(range), id: \.self) { value in
                Text(verbatim: "\(value)").tag(value)
            }
        }
        .pickerStyle(.menu)

        Picker("Unité", selection: $unitValue) {
            ForEach(units) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.menu)
    }

    // A single-choice options picker (menu), e.g. the list of known retreats.
    @ViewBuilder
    private func optionsPicker(_ options: [MessageTemplateOption]) -> some View {
        Picker(field.prompt, selection: $optionValue) {
            ForEach(options) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    MessageTemplateFormSheet(
        client: Client(name: "Marta Coelho", phone: "+41 79 123 45 67"),
        template: .reconnect
    )
}
