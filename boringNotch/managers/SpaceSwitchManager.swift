//
//  SpaceSwitchManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Watches Mission Control Space switches and publishes a notice for every
//  display whose current Space changed, so the notch can briefly show which
//  Space you landed on (its name and an icon).
//
//  Idea from Sapphire's desktop live activity (github.com/cshariq/Sapphire),
//  reimplemented for boring.notch's event bus and per-screen notch model.
//

import AppKit

/// What the notch shows after a Space switch.
struct SpaceSwitchInfo: Equatable {
    enum Kind: Equatable {
        /// A regular desktop. `number` matches Mission Control's "Desktop N"
        /// label: full-screen app Spaces on the same display don't count.
        case desktop(number: Int)
        /// A full-screen (or Split View) app Space.
        case fullScreen(appName: String?, appPID: pid_t?)
    }

    let kind: Kind
    /// The Space's identifier, so switching between two Spaces that would
    /// render identically still counts as a change.
    let spaceID: UInt64
}

@MainActor
final class SpaceSwitchManager {
    static let shared = SpaceSwitchManager()

    /// What `CGSCopyManagedDisplaySpaces` reports when "Displays have
    /// separate Spaces" is off: one Space list shared by every display.
    private static let sharedSpacesIdentifier = "Main"

    /// `type` values in the managed Spaces dictionaries.
    private static let desktopSpaceType = 0
    private static let fullScreenSpaceType = 4

    private var observer: NSObjectProtocol?
    /// Current Space ID per CGS display identifier, as of the last check.
    private var lastSpaceIDs: [String: UInt64] = [:]

    private init() {}

    var isRunning: Bool { observer != nil }

    func start() {
        guard observer == nil else { return }

        // Baseline only: starting (at launch or from Settings) shouldn't
        // announce the Space you're already on.
        lastSpaceIDs = Self.spaceIDs(in: Self.readCurrentSpaces())

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activeSpaceDidChange()
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        lastSpaceIDs = [:]
    }

    private func activeSpaceDidChange() {
        guard isRunning else { return }

        let current = Self.readCurrentSpaces()
        defer { lastSpaceIDs = Self.spaceIDs(in: current) }

        for space in current {
            // A display we haven't seen before (just connected, or Spaces
            // were rearranged) has no "previous" Space to compare with.
            guard let previous = lastSpaceIDs[space.displayIdentifier],
                  previous != space.info.spaceID else { continue }

            let screenUUIDs = Self.screenUUIDs(for: space.displayIdentifier)
            guard !screenUUIDs.isEmpty else { continue }

            NotchUIEventBus.events.send(
                .spaceSwitch(info: space.info, targetScreenUUIDs: screenUUIDs)
            )
        }
    }

    // MARK: - Reading Spaces

    private struct DisplaySpace {
        let displayIdentifier: String
        let info: SpaceSwitchInfo
    }

    private static func spaceIDs(in spaces: [DisplaySpace]) -> [String: UInt64] {
        Dictionary(
            spaces.map { ($0.displayIdentifier, $0.info.spaceID) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// The current Space of every display, from the WindowServer's managed
    /// Spaces list. Every key is read defensively: this is private API and
    /// its shape isn't guaranteed across macOS releases.
    private static func readCurrentSpaces() -> [DisplaySpace] {
        guard let unmanaged = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection()),
              let displays = unmanaged.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        return displays.compactMap { display -> DisplaySpace? in
            guard let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else {
                return nil
            }

            let currentID = uint64((display["Current Space"] as? [String: Any])?["id64"])
                ?? spaces.first(where: { ($0["is-current"] as? Bool) == true })
                    .flatMap { uint64($0["id64"]) }

            guard let currentID,
                  let space = spaces.first(where: { uint64($0["id64"]) == currentID }) else {
                return nil
            }

            let type = (space["type"] as? NSNumber)?.intValue ?? desktopSpaceType
            let kind: SpaceSwitchInfo.Kind

            switch type {
            case desktopSpaceType:
                let desktops = spaces.filter {
                    (($0["type"] as? NSNumber)?.intValue ?? desktopSpaceType) == desktopSpaceType
                }
                guard let index = desktops.firstIndex(where: { uint64($0["id64"]) == currentID }) else {
                    return nil
                }
                kind = .desktop(number: index + 1)
            case fullScreenSpaceType:
                kind = fullScreenKind(for: space)
            default:
                // Other system Spaces (e.g. the old Dashboard) have nothing
                // meaningful to show.
                return nil
            }

            return DisplaySpace(
                displayIdentifier: identifier,
                info: SpaceSwitchInfo(kind: kind, spaceID: currentID)
            )
        }
    }

    /// Full-screen Spaces list their app(s) as tiles; Split View has two.
    private static func fullScreenKind(for space: [String: Any]) -> SpaceSwitchInfo.Kind {
        let tiles = ((space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]]) ?? []

        var pids = tiles.compactMap { ($0["pid"] as? NSNumber)?.int32Value }
        if pids.isEmpty, let pid = (space["pid"] as? NSNumber)?.int32Value {
            pids = [pid]
        }

        var names = pids.compactMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        if names.isEmpty {
            names = tiles.compactMap { $0["appName"] as? String }
        }

        let uniqueNames = names.reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }

        return .fullScreen(
            appName: uniqueNames.isEmpty ? nil : uniqueNames.joined(separator: " & "),
            appPID: pids.first
        )
    }

    /// Notch screens a CGS display identifier maps to. With shared Spaces
    /// ("Main"), a switch changes every display at once.
    private static func screenUUIDs(for displayIdentifier: String) -> [String] {
        let screenUUIDs = NSScreen.screens.compactMap(\.displayUUID)

        if displayIdentifier == sharedSpacesIdentifier {
            return screenUUIDs
        }

        return screenUUIDs.filter {
            $0.caseInsensitiveCompare(displayIdentifier) == .orderedSame
        }
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}

// MARK: - Private CGS API
// Same connection signature as boringNotch/private/CGSSpace.swift, so both
// declarations agree on the symbol's type.
private typealias CGSConnectionID = UInt
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?
