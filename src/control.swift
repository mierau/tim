import Foundation

enum ControlEvent {
  case character(Character)
  case key(Int)
  case tab(shift: Bool)
  case focusGained
  case focusLost
}

enum ControlEventResult {
  case handled
  case unhandled
}

enum FocusTarget {
  case document
  case findField
}

protocol Control {
  mutating func handle(event: ControlEvent, context: inout EditorState) -> ControlEventResult
  mutating func updateFocus(_ focused: Bool)
}
