//
//  NotificationTrayView.swift
//  boringNotch
//
//  The open notch's Notifications tab: every mirrored notification that
//  hasn't been opened or cleared yet, newest first.
//

import SwiftUI

struct NotificationTrayView: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if manager.trayNotifications.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(manager.trayNotifications) { notification in
                            NotificationTrayRow(notification: notification)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.25), value: manager.trayNotifications)
        // Looking at the tray is what reads them, including ones that
        // arrive while it's open.
        .onAppear { manager.markAllRead() }
        .onChange(of: manager.unreadCount) { _, _ in manager.markAllRead() }
        // Without "always show tabs" the tab disappears once the tray is
        // empty, which would leave the user on a tab they can't switch away
        // from, so go back to Home.
        .onChange(of: manager.trayNotifications.isEmpty) { _, isEmpty in
            guard isEmpty, !coordinator.alwaysShowTabs else { return }
            withAnimation(.smooth) { coordinator.currentView = .home }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Notifications")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if !manager.trayNotifications.isEmpty {
                Text("\(manager.trayNotifications.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !manager.trayNotifications.isEmpty {
                Button("Clear All") {
                    manager.clearTray()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No notifications")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct NotificationTrayRow: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    let notification: SystemNotification

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: openSourceApp) {
                HStack(alignment: .top, spacing: 10) {
                    NotificationSourceIcon(bundleID: notification.bundleID, size: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(notification.appName ?? String(localized: "Notification"))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)

                            Text(notification.receivedAt, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                        }

                        if let title = notification.title, title != notification.appName {
                            Text(title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }

                        if let subtitle = notification.subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let body = notification.body {
                            Text(body)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary.opacity(0.9))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Keep text clear of the remove button.
                    .padding(.trailing, 20)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(isHovering ? 0.1 : 0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(notification.appName ?? "App") notification")
            .accessibilityHint("Opens \(notification.appName ?? "the app")")

            Button {
                manager.removeFromTray(notification.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel("Remove notification")
        }
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.15), value: isHovering)
    }

    private func openSourceApp() {
        Task {
            guard await manager.open(notification) else { return }
            manager.removeFromTray(notification.id)
        }
    }
}
