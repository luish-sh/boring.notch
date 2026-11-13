//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    /// Unread items behind this tab; 0 shows no badge.
    var badgeCount: Int = 0
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .overlay(alignment: .topTrailing) {
                    if badgeCount > 0 {
                        Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 12, minHeight: 12)
                            .background(Color.effectiveAccent, in: Capsule())
                            .offset(x: 8, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.smooth(duration: 0.2), value: badgeCount)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
        .accessibilityValue(badgeCount > 0 ? Text("\(badgeCount) unread") : Text(""))
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        Log.general.debug("Tapped")
    }
}
