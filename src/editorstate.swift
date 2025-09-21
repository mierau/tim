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
    state.bufferDidChange()
  }
}

struct EditorState {
  struct FindMatch {
    let line: Int
    let range: Range<Int>
  }

  struct FindState {
    enum Focus {
      case field
      case document
    }

    var active: Bool = false
    var query: String = ""
    var useRegex: Bool = false
    var regexError: String?
    var matches: [FindMatch] = []
    var currentIndex: Int = 0
    var originalCursor: (line: Int, column: Int)?
    var originalSelectionStart: (line: Int, column: Int)?
    var originalSelectionEnd: (line: Int, column: Int)?
    var cursorPosition: Int = 0
    var focus: Focus = .field
    var cursorVisible: Bool = true
    var lastBlinkTime: Date = Date()
  }

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
  var find: FindState

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
    self.find = FindState()
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
    if find.active && find.focus == .field {
      let now = Date()
      if now.timeIntervalSince(find.lastBlinkTime) > 0.5 {
        find.cursorVisible.toggle()
        find.lastBlinkTime = now
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
  }

  mutating func markLayoutDirty() {
    layoutGeneration &+= 1
    layoutCache.invalidateAll()
  }

  mutating func bufferDidChange(lineRange: Range<Int>? = nil) {
    layoutGeneration &+= 1
    if let range = lineRange {
      layoutCache.invalidateLines(in: range)
    } else {
      layoutCache.invalidateAll()
    }
    refreshDirtyFlag()
    if find.active, !find.query.isEmpty {
      recomputeFindMatches()
    }
  }
}

extension EditorState {
  mutating func enterFindMode() {
    guard !find.active else { return }
    find.active = true
    find.query = ""
    find.useRegex = false
    find.regexError = nil
    find.matches = []
    find.currentIndex = 0
    find.originalCursor = (cursorLine, cursorColumn)
    find.originalSelectionStart = selectionStart
    find.originalSelectionEnd = selectionEnd
    find.cursorPosition = 0
    find.focus = .field
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    needsRedraw = true
  }

  mutating func exitFindMode(restoreSelection: Bool = true) {
    guard find.active else { return }
    if restoreSelection {
      if let origin = find.originalCursor {
        cursorLine = origin.line
        cursorColumn = origin.column
      }
      selectionStart = find.originalSelectionStart
      selectionEnd = find.originalSelectionEnd
    } else {
      selectionStart = nil
      selectionEnd = nil
    }
    selectionMode = .none
    find = FindState()
    pinCursorToView = true
    needsRedraw = true
  }

  mutating func appendFindCharacter(_ char: Character) {
    guard find.active, find.focus == .field else { return }
    let insertIndex = find.query.index(find.query.startIndex, offsetBy: find.cursorPosition)
    find.query.insert(char, at: insertIndex)
    find.cursorPosition += 1
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    recomputeFindMatches()
  }

  mutating func deleteFindBackward() {
    guard find.active, find.focus == .field, find.cursorPosition > 0 else { return }
    let removeIndex = find.query.index(find.query.startIndex, offsetBy: find.cursorPosition)
    let beforeIndex = find.query.index(before: removeIndex)
    find.query.removeSubrange(beforeIndex..<removeIndex)
    find.cursorPosition -= 1
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    recomputeFindMatches()
  }

  mutating func deleteFindForward() {
    guard find.active, find.focus == .field, find.cursorPosition < find.query.count else { return }
    let start = find.query.index(find.query.startIndex, offsetBy: find.cursorPosition)
    let end = find.query.index(after: start)
    find.query.removeSubrange(start..<end)
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    recomputeFindMatches()
  }

  mutating func moveFindSelection(forward: Bool) {
    guard find.active, !find.matches.isEmpty else { return }
    if forward {
      find.currentIndex = (find.currentIndex + 1) % find.matches.count
    } else {
      find.currentIndex = (find.currentIndex - 1 + find.matches.count) % find.matches.count
    }
    applyCurrentFindMatch()
  }

  mutating func recomputeFindMatches() {
    guard find.active else { return }
    let trimmed = find.query
    if trimmed.isEmpty {
      find.matches = []
      find.regexError = nil
      find.useRegex = false
      find.currentIndex = 0
      find.cursorPosition = 0
      find.cursorVisible = true
      find.lastBlinkTime = Date()
      if let origin = find.originalCursor {
        cursorLine = origin.line
        cursorColumn = origin.column
      }
      selectionStart = find.originalSelectionStart
      selectionEnd = find.originalSelectionEnd
      needsRedraw = true
      return
    }

    let computation = EditorState.computeFindMatches(buffer: buffer, query: trimmed)
    find.useRegex = computation.useRegex
    find.regexError = computation.errorMessage
    if let _ = computation.errorMessage {
      find.matches = []
      find.currentIndex = 0
      find.cursorPosition = min(find.cursorPosition, find.query.count)
      find.cursorVisible = true
      find.lastBlinkTime = Date()
      selectionStart = nil
      selectionEnd = nil
      needsRedraw = true
      return
    }

    find.matches = computation.matches
    if find.matches.isEmpty {
      find.currentIndex = 0
      find.cursorPosition = min(find.cursorPosition, find.query.count)
      find.cursorVisible = true
      find.lastBlinkTime = Date()
      selectionStart = nil
      selectionEnd = nil
      needsRedraw = true
      return
    }
    find.currentIndex = 0
    find.cursorPosition = min(find.cursorPosition, find.query.count)
    applyCurrentFindMatch()
  }

  mutating func applyCurrentFindMatch() {
    guard find.active, !find.matches.isEmpty else { return }
    let match = find.matches[find.currentIndex]
    selectionStart = (match.line, match.range.lowerBound)
    selectionEnd = (match.line, match.range.upperBound)
    selectionMode = .character(anchorLine: match.line, anchorColumn: match.range.lowerBound)
    cursorLine = match.line
    cursorColumn = match.range.upperBound
    clampCursor()
    pinCursorToView = true
    needsRedraw = true
  }

  mutating func moveFindCursorLeft() {
    guard find.active, find.focus == .field else { return }
    find.cursorPosition = max(0, find.cursorPosition - 1)
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    needsRedraw = true
  }

  mutating func moveFindCursorRight() {
    guard find.active, find.focus == .field else { return }
    find.cursorPosition = min(find.cursorPosition + 1, find.query.count)
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    needsRedraw = true
  }

  mutating func moveFindCursorToStart() {
    guard find.active, find.focus == .field else { return }
    find.cursorPosition = 0
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    needsRedraw = true
  }

  mutating func moveFindCursorToEnd() {
    guard find.active, find.focus == .field else { return }
    find.cursorPosition = find.query.count
    find.cursorVisible = true
    find.lastBlinkTime = Date()
    needsRedraw = true
  }

  mutating func setFindFocus(_ focus: FindState.Focus) {
    guard find.active else { return }
    if find.focus != focus {
      find.focus = focus
      if focus == .field {
        find.cursorVisible = true
        find.lastBlinkTime = Date()
      } else {
        cursorVisible = true
        lastBlinkTime = Date()
      }
      needsRedraw = true
    }
  }

  private static func computeFindMatches(buffer: [String], query: String) -> (matches: [FindMatch], useRegex: Bool, errorMessage: String?) {
    if query.count >= 2, query.first == "/", query.last == "/" {
      let pattern = String(query.dropFirst().dropLast())
      do {
        let regex = try NSRegularExpression(pattern: pattern)
        var results: [FindMatch] = []
        for (lineIndex, line) in buffer.enumerated() {
          let nsLine = line as NSString
          let nsRange = NSRange(location: 0, length: nsLine.length)
          regex.enumerateMatches(in: line, options: [], range: nsRange) { match, _, _ in
            guard let match = match, match.range.length > 0,
              let swiftRange = Range(match.range, in: line)
            else { return }
            let start = line.distance(from: line.startIndex, to: swiftRange.lowerBound)
            let end = line.distance(from: line.startIndex, to: swiftRange.upperBound)
            results.append(FindMatch(line: lineIndex, range: start..<end))
          }
        }
        return (results, true, nil)
      } catch {
        return ([], true, "Invalid regular expression")
      }
    } else {
      var results: [FindMatch] = []
      for (lineIndex, line) in buffer.enumerated() {
        var searchStart = line.startIndex
        while searchStart < line.endIndex {
          if let range = line[searchStart...].range(of: query, options: .caseInsensitive) {
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let end = line.distance(from: line.startIndex, to: range.upperBound)
            results.append(FindMatch(line: lineIndex, range: start..<end))
            if range.upperBound < line.endIndex {
              searchStart = range.upperBound
            } else {
              break
            }
          } else {
            break
          }
        }
      }
      return (results, false, nil)
    }
  }
}
