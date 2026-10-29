import Foundation
import XCTest
@testable import TouchDynamics

/// A clock the tests advance by hand.
final class ManualClock: TouchDynamicsClock, @unchecked Sendable {
    var time: TimeInterval
    init(_ time: TimeInterval = 0) { self.time = time }
    func now() -> TimeInterval { time }
}

/// Records engine commands.
@MainActor
final class CommandRecorder {
    private(set) var commands: [EngineCommand] = []

    func record(_ command: EngineCommand) { commands.append(command) }
    func clear() { commands.removeAll() }

    var last: EngineCommand? { commands.last }

    var illuminates: [TouchSession] {
        commands.compactMap { if case .illuminate(let s) = $0 { return s } else { return nil } }
    }
    var tracks: [TouchSession] {
        commands.compactMap { if case .track(let s) = $0 { return s } else { return nil } }
    }
    var releases: [(TouchSession, Bool)] {
        commands.compactMap { if case .release(let s, let r) = $0 { return (s, r) } else { return nil } }
    }
    var dissipates: [(TouchSession, Bool)] {
        commands.compactMap { if case .dissipate(let s, let i) = $0 { return (s, i) } else { return nil } }
    }
    var longPresses: [TouchSession] {
        commands.compactMap { if case .longPress(let s) = $0 { return s } else { return nil } }
    }
    var resets: Int {
        commands.filter { $0 == .reset }.count
    }
}

extension TouchIdentifier {
    static func test(_ n: UInt) -> TouchIdentifier { TouchIdentifier(rawValue: n) }
}

@MainActor
func makeEngine(
    configuration: GestureConfiguration = .init(),
    bounds: CGRect = CGRect(x: 0, y: 0, width: 320, height: 60),
    clock: ManualClock = ManualClock()
) -> (TouchInteractionEngine, CommandRecorder) {
    let engine = TouchInteractionEngine(configuration: configuration, bounds: bounds, clock: clock)
    let recorder = CommandRecorder()
    engine.onCommand = { recorder.record($0) }
    return (engine, recorder)
}
