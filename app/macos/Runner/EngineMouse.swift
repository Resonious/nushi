import Foundation

/// What Flutter's engine has been told of the mouse, call for call, and the
/// releases it must be told that never reached it (ADR 0080, amended
/// 2026-11-19). Plain state with no AppKit calls, so `make test-window`
/// runs it.
///
/// The engine (FlutterViewController.mm, its MouseState) keeps one set of
/// every button it was told went down and not up, and whether Flutter has
/// a press: with no button in the set it sends a release (or a hover), with
/// any a move (or a press). A release of any button that never reaches it
/// (a window drag, a menu's or a web view's own tracking took it) leaves
/// that button in the set for good: each later move of the pointer goes to
/// Flutter as a drag with nothing held (a pane's edge follows the pointer),
/// and each later press of another button, or of the same one, as a move
/// of that old press (a press on an edge does nothing).
///
/// This keeps the same set from the same calls (NushiViewController makes
/// every one through it), so it can't disagree with the engine. A button in
/// it that isn't held is [stale]: the engine is told its release, once, and
/// the real release, if it still comes, is dropped ([real(released:)]).
struct EngineMouse {
  /// What the engine sends Flutter for a call, as it decides it.
  enum Phase: Equatable {
    /// Nothing: the call changed only what the engine keeps.
    case none
    case add, remove, hover, down, move, up
    case panZoomStart, panZoomUpdate, panZoomEnd
  }

  /// A trackpad gesture's kind, as the engine tells them apart.
  enum Gesture: CaseIterable {
    case scroll, magnify, rotate
  }

  /// A gesture event's phase (NSEvent.Phase, momentum aside).
  enum GesturePhase {
    case none, mayBegin, began, changed, stationary, ended, cancelled
  }

  /// The engine's set: bit n is button n (NSEvent.buttonNumber: 0 the
  /// left, 1 the right, 2 and on the others), as the engine keeps them.
  private(set) var buttons: UInt64 = 0
  /// Whether Flutter has a press (the engine's flutter_state_is_down).
  private(set) var isDown = false
  /// Whether the pointer is added (flutter_state_is_added).
  private(set) var isAdded = false
  /// The pointer left with a button held: removed once the last is let go
  /// (has_pending_exit).
  private(set) var pendingExit = false
  /// The buttons whose release the engine was told by [letGo], the real
  /// one not seen since: it's dropped if it comes.
  private(set) var owed: UInt64 = 0

  /// Whether Flutter has a trackpad gesture going: its pan/zoom pointer
  /// (flutter_state_is_pan_zoom_started).
  private(set) var panZooming = false
  /// Each kind's last start or end phase, as the engine keeps them
  /// (pan_gesture_phase and the others): one still begun or changed holds
  /// back the end of the rest.
  private var gesturePhases: [Gesture: GesturePhase] = [:]

  /// Button [n]'s bit; none for a number the engine can't hold.
  static func bit(_ n: Int) -> UInt64 { (0..<64).contains(n) ? 1 << UInt64(n) : 0 }

  /// The buttons in [set], lowest first.
  static func numbers(_ set: UInt64) -> [Int] { (0..<64).filter { set & (1 << UInt64($0)) != 0 } }

  // The engine's own calls, as it handles them.

  /// mouseDown, rightMouseDown, otherMouseDown.
  mutating func pressed(_ n: Int) -> Phase {
    buttons |= Self.bit(n)
    suspect &= ~Self.bit(n)
    return dispatch()
  }

  /// mouseUp, rightMouseUp, otherMouseUp.
  mutating func released(_ n: Int) -> Phase {
    buttons &= ~Self.bit(n)
    suspect &= ~Self.bit(n)
    return dispatch()
  }

  /// mouseMoved and the dragged events. An event between two looks says
  /// the events are flowing: what a look saw stale may be queued yet.
  mutating func moved() -> Phase {
    suspect = 0
    return dispatch()
  }

  /// mouseEntered: back in before the last button was let go cancels the
  /// removal; else the pointer is added.
  mutating func entered() -> Phase {
    if pendingExit {
      pendingExit = false
      return .none
    }
    return send(.add)
  }

  /// mouseExited: with a button held the removal waits for its release.
  mutating func exited() -> Phase {
    if buttons != 0 {
      pendingExit = true
      return .none
    }
    return send(.remove)
  }

  /// scrollWheel, magnifyWithEvent, rotateWithEvent: a gesture's event
  /// of [kind] in [phase], [momentum] when it's the momentum after it.
  mutating func gesture(_ kind: Gesture, _ phase: GesturePhase, momentum: Bool = false) -> Phase {
    switch phase {
    case .began, .mayBegin:
      gesturePhases[kind] = phase
      if panZooming { return .none }  // another kind started it
      isAdded = true
      panZooming = true
      return .panZoomStart
    case .changed:
      isAdded = true
      return .panZoomUpdate
    case .ended, .cancelled:
      gesturePhases[kind] = phase
      // The engine ignores an end with no gesture going, and one while
      // another kind is still begun or changed.
      guard panZooming, !gesturePhases.values.contains(where: { $0 == .began || $0 == .changed }) else {
        return .none
      }
      (panZooming, gesturePhases) = (false, [:])
      return .panZoomEnd
    case .none where !momentum: return send(.hover)  // a mouse's wheel
    default: return .none  // momentum: the framework makes its own
    }
  }

  /// Whether an end of [kind] the engine never had leaves its gesture going:
  /// it holds that kind begun or changed.
  func owesEnd(_ kind: Gesture) -> Bool {
    panZooming && (gesturePhases[kind] == .began || gesturePhases[kind] == .changed || gesturePhases[kind] == .mayBegin)
  }

  private mutating func dispatch() -> Phase {
    send(buttons == 0 ? (isDown ? .up : .hover) : (isDown ? .move : .down))
  }

  private mutating func send(_ phase: Phase) -> Phase {
    if isAdded, phase == .add { return .none }
    isAdded = true  // an event before the pointer's add has one made first
    switch phase {
    case .down: isDown = true
    case .up:
      isDown = false
      if pendingExit { reset() }  // and the removal that waited
    case .remove: reset()
    default: break
    }
    return phase
  }

  private mutating func reset() {
    (isAdded, isDown, pendingExit, buttons) = (false, false, false, 0)
  }

  // What the guard decides.

  /// The buttons the engine holds that aren't [held] now (pressedMouseButtons:
  /// the live state, which runs ahead of the events still queued): each is
  /// owed its release. A button held is never one.
  func stale(held: UInt64) -> [Int] { Self.numbers(buttons & ~held) }

  /// The buttons [look] found stale last time, with no call for them since.
  private var suspect: UInt64 = 0

  /// A look between events (a timer's): the buttons stale now that were
  /// stale at the last look too, with no call for them between. Once alone
  /// could be a release still queued (the live state runs ahead of the
  /// events); a release queued at one look has been handled by the next.
  mutating func look(held: UInt64) -> [Int] {
    let now = buttons & ~held
    defer { suspect = now }
    return Self.numbers(now & suspect)
  }

  /// A real press of [n] is about to go on, with [held] the buttons held
  /// now: the engine still holding [n] means its last release never came
  /// (no button goes down twice), and any other it holds that isn't held
  /// lost its release too. Those are owed their releases first, or the
  /// engine would send this press as a move of the old one. A real press
  /// also means a real release still to come is this one's, not one owed.
  mutating func real(pressed n: Int, held: UInt64) -> [Int] {
    owed &= ~Self.bit(n)
    return stale(held: held & ~Self.bit(n))
  }

  /// The engine is told the release of [n] it never had: the real one, if
  /// it comes, is dropped, unless [owing] is false (a press of [n] is what
  /// showed it stale: the old press's release can't come after it).
  mutating func letGo(_ n: Int, owing: Bool = true) -> Phase {
    if owing { owed |= Self.bit(n) }
    return released(n)
  }

  /// A real release of [n] came: whether it goes on to the engine, not when
  /// the engine already had one made up for it.
  mutating func real(released n: Int) -> Bool {
    guard owed & Self.bit(n) != 0 else { return true }
    owed &= ~Self.bit(n)
    return false
  }

  /// Whether a release of [n] coming now would be dropped.
  func owes(_ n: Int) -> Bool { owed & Self.bit(n) != 0 }
}

/// A button's name for the log: no more than which one it is.
func buttonName(_ n: Int) -> String {
  switch n {
  case 0: "left"
  case 1: "right"
  default: "other \(n)"
  }
}
