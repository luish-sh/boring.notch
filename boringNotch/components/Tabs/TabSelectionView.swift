//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Notifications", icon: "bell.fill", view: .notifications)
]

/// The tabs the open notch should offer right now. Home is always there;
/// each other tab appears when its feature is on and it either has
/// something in it or "always show tabs" is set. A single tab means no tab
/// bar at all.
@MainActor
func visibleNotchTabs(shelfIsEmpty: Bool, trayIsEmpty: Bool) -> [TabModel] {
    let alwaysShow = BoringViewCoordinator.shared.alwaysShowTabs
    return tabs.filter { tab in
        switch tab.view {
        case .home:
            return true
        case .shelf:
            return Defaults[.boringShelf] && (alwaysShow || !shelfIsEmpty)
        case .notifications:
            return Defaults[.notificationLiveActivity] && Defaults[.notificationTray]
                && (alwaysShow || !trayIsEmpty)
        }
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var notificationManager = SystemNotificationManager.shared
    let visibleTabs: [TabModel]
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(
                        label: tab.label,
                        icon: tab.icon,
                        selected: coordinator.currentView == tab.view,
                        badgeCount: tab.view == .notifications ? notificationManager.unreadCount : 0
                    ) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel(camera: CameraModel()))
}
