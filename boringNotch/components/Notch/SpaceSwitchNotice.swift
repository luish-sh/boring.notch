//
//  SpaceSwitchNotice.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  The closed-notch notice shown after switching Spaces: an icon on one
//  side of the notch and the Space's name on the other.
//

import AppKit
import SwiftUI

struct SpaceSwitchNotice: View {
    let info: SpaceSwitchInfo
    let notchWidth: CGFloat
    let height: CGFloat

    /// Both sides hold the icon and the label stacked, one of them hidden,
    /// so they always measure the same: the black centre stays under the
    /// physical notch however long the (translated) name is. Same approach
    /// as `PowerStatusNotice`.
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                icon
                label.hidden()
            }

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth + 10)

            ZStack(alignment: .trailing) {
                icon.hidden()
                label
            }
        }
        .frame(height: height, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var title: Text {
        switch info.kind {
        case .desktop(let number):
            return Text("Desktop \(number)")
        case .fullScreen(let appName, _):
            if let appName {
                return Text(verbatim: appName)
            }
            return Text("Full Screen")
        }
    }

    private var label: some View {
        title
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
    }

    @ViewBuilder
    private var icon: some View {
        switch info.kind {
        case .desktop:
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        case .fullScreen(_, let pid):
            if let appIcon = pid.flatMap({ NSRunningApplication(processIdentifier: $0)?.icon }) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
