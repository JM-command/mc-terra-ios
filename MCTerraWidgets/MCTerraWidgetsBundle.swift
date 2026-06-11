//
//  MCTerraWidgetsBundle.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//

import WidgetKit
import SwiftUI

/// Registers every widget exposed by the extension:
/// - the running-session Live Activity (lock screen / Dynamic Island),
/// - the home-screen "Prochaine séance / Agenda" widget,
/// - the home-screen "Revenus du mois" widget,
/// - the home-screen "Clients récents" widget.
@main
struct MCTerraWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MCTerraWidgetsLiveActivity()
        NextSessionWidget()
        RevenueWidget()
        RecentClientsWidget()
    }
}
