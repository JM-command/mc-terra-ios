//
//  ContactPickerView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

import WidgetKit

#if os(iOS)
import ContactsUI

/// A UIViewControllerRepresentable wrapper around CNContactPickerViewController
/// that allows multiple contact selection and imports them as Clients.
struct ContactPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(context: context, dismiss: dismiss)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let modelContext: ModelContext
        let dismiss: DismissAction

        init(context: ModelContext, dismiss: DismissAction) {
            self.modelContext = context
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            importContact(contact)
            // Reflect the imported client in the home-screen widgets.
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            for contact in contacts {
                importContact(contact)
            }
            // Reflect the imported clients in the home-screen widgets.
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        }

        private func importContact(_ contact: CNContact) {
            let givenName = contact.givenName.trimmingCharacters(in: .whitespaces)
            let familyName = contact.familyName.trimmingCharacters(in: .whitespaces)
            let fullName = [givenName, familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

            let phoneNumber = contact.phoneNumbers.first?.value.stringValue ?? ""

            if !fullName.isEmpty {
                let client = Client(name: fullName, phone: phoneNumber, language: "fr")
                modelContext.insert(client)
            }
        }
    }
}
#else
/// Fallback for macOS: empty view (CNContactPickerViewController is iOS-only).
struct ContactPickerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Contact import is not available on macOS")
                .foregroundStyle(.secondary)
        }
        .onAppear { dismiss() }
    }
}
#endif
