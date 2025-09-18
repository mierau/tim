import Foundation

enum SelectionMode {
  case none
  case character(anchorLine: Int, anchorColumn: Int)
  case word(anchorLine: Int, anchorStart: Int, anchorEnd: Int)
  case line(anchorLine: Int)
}

enum UndoOperationKind {
  case insert
  case deleteBackward
  case deleteForward
  case paste
  case other

  var coalesces: Bool {
    switch self {
    case .insert, .deleteBackward:
      return true
    default:
      return false
    }
  }
}

struct UndoSnapshot {
  let buffer: [String]
  let cursorLine: Int
  let cursorColumn: Int
  let selectionStart: (line: Int, column: Int)?
  let selectionEnd: (line: Int, column: Int)?
  let scrollOffset: Int
  let visualScrollOffset: Int

  init(state: EditorState) {
    self.buffer = state.buffer
    self.cursorLine = state.cursorLine
    self.cursorColumn = state.cursorColumn
    self.selectionStart = state.selectionStart
    self.selectionEnd = state.selectionEnd
    self.scrollOffset = state.scrollOffset
    self.visualScrollOffset = state.visualScrollOffset
  }

  func apply(to state: inout EditorState) {
    state.buffer = buffer
    state.cursorLine = cursorLine
    state.cursorColumn = cursorColumn
    state.selectionStart = selectionStart
    state.selectionEnd = selectionEnd
    state.scrollOffset = scrollOffset
    state.visualScrollOffset = visualScrollOffset
    state.needsRedraw = true
    state.pinCursorToView = true
    state.refreshDirtyFlag()
  }
}

struct EditorState {
  var buffer: [String]
  var cursorLine: Int
  var cursorColumn: Int
  var scrollOffset: Int
  var visualScrollOffset: Int
  var cursorVisible: Bool
  var lastBlinkTime: Date
  var lastClickTime: Date?
  var lastClickLine: Int?
  var lastClickColumn: Int?
  var lastClickCount: Int
  var selectionStart: (line: Int, column: Int)?
  var selectionEnd: (line: Int, column: Int)?
  var needsRedraw: Bool
  var isDragging: Bool
  var selectionMode: SelectionMode
  var isScrollbarDragging: Bool
  var pinCursorToView: Bool
  var filePath: String?
  var shouldQuit: Bool
  var isDirty: Bool
  var savedBuffer: [String]
  var undoStack: [UndoSnapshot]
  var redoStack: [UndoSnapshot]
  var lastUndoOperation: UndoOperationKind?
  var lastUndoTimestamp: Date?
  var layoutCache: LayoutCache
  var layoutGeneration: Int

  var displayFilename: String {
    if let filePath { return URL(fileURLWithPath: filePath).lastPathComponent }
    return "untitled.txt"
  }

  init() {
    self.buffer = [""]
    self.cursorLine = 0
    self.cursorColumn = 0
    self.scrollOffset = 0
    self.cursorVisible = true
    self.lastBlinkTime = Date()
    self.lastClickTime = nil
    self.lastClickLine = nil
    self.lastClickColumn = nil
    self.lastClickCount = 0
    self.selectionStart = nil
    self.selectionEnd = nil
    self.needsRedraw = true
    self.isDragging = false
    self.selectionMode = .none
    self.visualScrollOffset = 0
    self.isScrollbarDragging = false
    self.pinCursorToView = true
    self.filePath = nil
    self.shouldQuit = false
    self.isDirty = false
    self.savedBuffer = buffer
    self.undoStack = []
    self.redoStack = []
    self.lastUndoOperation = nil
    self.lastUndoTimestamp = nil
    self.layoutCache = LayoutCache()
    self.layoutGeneration = 0
  }

  mutating func clampCursor() {
    if buffer.isEmpty { buffer = [""] }
    cursorLine = max(0, min(cursorLine, buffer.count - 1))
    let lineLength = buffer[cursorLine].count
    cursorColumn = max(0, min(cursorColumn, lineLength))
  }

  mutating func updateCursorBlink() {
    if hasSelection {
      if cursorVisible {
        cursorVisible = false
        needsRedraw = true
      }
      return
    }
    let now = Date()
    if now.timeIntervalSince(lastBlinkTime) > 0.5 {
      cursorVisible.toggle()
      lastBlinkTime = now
      needsRedraw = true
    }
  }

  mutating func showCursor() {
    if !hasSelection {
      cursorVisible = true
      lastBlinkTime = Date()
      needsRedraw = true
    }
  }

  var hasSelection: Bool { selectionStart != nil && selectionEnd != nil }

  mutating func clearSelection() {
    selectionStart = nil
    selectionEnd = nil
    showCursor()
    selectionMode = .none
  }

  mutating func startSelection() {
    selectionStart = (cursorLine, cursorColumn)
    selectionEnd = (cursorLine, cursorColumn)
    selectionMode = .character(anchorLine: cursorLine, anchorColumn: cursorColumn)
  }

  mutating func updateSelection() {
    if selectionStart != nil { selectionEnd = (cursorLine, cursorColumn) }
  }

  func isPositionSelected(line: Int, column: Int) -> Bool {
    guard let start = selectionStart, let end = selectionEnd else { return false }
    let (startPos, endPos) = normalizeSelection(start: start, end: end)
    if line < startPos.line || line > endPos.line { return false }
    if line == startPos.line && line == endPos.line {
      return column >= startPos.column && column < endPos.column
    } else if line == startPos.line {
      return column >= startPos.column
    } else if line == endPos.line {
      return column < endPos.column
    } else {
      return true
    }
  }

  func normalizeSelection(start: (line: Int, column: Int), end: (line: Int, column: Int)) -> (
    (line: Int, column: Int), (line: Int, column: Int)
  ) {
    if start.line < end.line || (start.line == end.line && start.column <= end.column) {
      return (start, end)
    } else {
      return (end, start)
    }
  }

  mutating func refreshDirtyFlag() {
    isDirty = buffer != savedBuffer
    markLayoutDirty()
  }

  mutating func markLayoutDirty() {
    layoutGeneration &+= 1
    layoutCache.invalidate()
  }
}
