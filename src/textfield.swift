import Foundation

struct TextFieldState {
  var text: String = ""
  var cursor: Int = 0
  var selection: Range<Int>? = nil
  var selectionAnchor: Int? = nil
  var viewOffset: Int = 0

  mutating func reset(text: String = "") {
    self.text = text
    cursor = min(cursor, text.count)
    cursor = min(max(0, cursor), text.count)
    clearSelection()
    viewOffset = min(viewOffset, cursor)
  }

  mutating func insert(_ character: Character) {
    _ = removeSelectionIfNeeded()
    let index = text.index(text.startIndex, offsetBy: cursor)
    text.insert(character, at: index)
    cursor += 1
    clearSelection()
    clampViewOffset()
  }

  mutating func insert(contentsOf string: String) {
    _ = removeSelectionIfNeeded()
    let insertIndex = text.index(text.startIndex, offsetBy: cursor)
    text.insert(contentsOf: string, at: insertIndex)
    cursor += string.count
    clearSelection()
    clampViewOffset()
  }

  mutating func deleteBackward() {
    if removeSelectionIfNeeded() { return }
    guard cursor > 0 else { return }
    let start = text.index(text.startIndex, offsetBy: cursor - 1)
    text.remove(at: start)
    cursor -= 1
    clampViewOffset()
  }

  mutating func deleteForward() {
    if removeSelectionIfNeeded() { return }
    guard cursor < text.count else { return }
    let start = text.index(text.startIndex, offsetBy: cursor)
    text.remove(at: start)
    clampViewOffset()
  }

  func selectedText() -> String? {
    guard let range = selection, !range.isEmpty else { return nil }
    let startIndex = text.index(text.startIndex, offsetBy: range.lowerBound)
    let endIndex = text.index(text.startIndex, offsetBy: range.upperBound)
    return String(text[startIndex..<endIndex])
  }

  @discardableResult
  mutating func deleteSelectionContents() -> String? {
    guard let range = selection, !range.isEmpty else { return nil }
    let startIndex = text.index(text.startIndex, offsetBy: range.lowerBound)
    let endIndex = text.index(text.startIndex, offsetBy: range.upperBound)
    let removed = String(text[startIndex..<endIndex])
    text.removeSubrange(startIndex..<endIndex)
    cursor = range.lowerBound
    clearSelection()
    clampViewOffset()
    return removed
  }

  mutating func deleteWordBackward() {
    if removeSelectionIfNeeded() { return }
    guard cursor > 0 else { return }
    let start = wordBoundaryLeft(from: cursor)
    guard start < cursor else { return }
    let startIndex = text.index(text.startIndex, offsetBy: start)
    let endIndex = text.index(text.startIndex, offsetBy: cursor)
    text.removeSubrange(startIndex..<endIndex)
    cursor = start
    clampViewOffset()
  }

  mutating func moveCursorLeft(expandSelection: Bool = false) {
    if !expandSelection, let range = selection, !range.isEmpty {
      cursor = range.lowerBound
      clearSelection()
      clampViewOffset()
      return
    }
    guard cursor > 0 else {
      if !expandSelection { clearSelection() }
      return
    }
    let originalCursor = cursor
    cursor -= 1
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func moveCursorRight(expandSelection: Bool = false) {
    if !expandSelection, let range = selection, !range.isEmpty {
      cursor = range.upperBound
      clearSelection()
      clampViewOffset()
      return
    }
    guard cursor < text.count else {
      if !expandSelection { clearSelection() }
      return
    }
    let originalCursor = cursor
    cursor += 1
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func moveCursorToStart(expandSelection: Bool = false) {
    if !expandSelection, let range = selection, !range.isEmpty {
      cursor = range.lowerBound
      clearSelection()
      clampViewOffset()
      return
    }
    let originalCursor = cursor
    cursor = 0
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func moveCursorToEnd(expandSelection: Bool = false) {
    if !expandSelection, let range = selection, !range.isEmpty {
      cursor = range.upperBound
      clearSelection()
      clampViewOffset()
      return
    }
    let originalCursor = cursor
    cursor = text.count
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func moveCursorWordLeft(expandSelection: Bool = false) {
    if !expandSelection, let range = selection, !range.isEmpty {
      cursor = range.lowerBound
      clearSelection()
      clampViewOffset()
      return
    }
    guard cursor > 0 else {
      if !expandSelection { clearSelection() }
      return
    }
    let originalCursor = cursor
    cursor = wordBoundaryLeft(from: cursor)
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func moveCursorWordRight(expandSelection: Bool = false) {
    if !expandSelection, let range = selection, !range.isEmpty {
      cursor = range.upperBound
      clearSelection()
      clampViewOffset()
      return
    }
    guard cursor < text.count else {
      if !expandSelection { clearSelection() }
      return
    }
    let originalCursor = cursor
    cursor = wordBoundaryRight(from: cursor)
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func setCursor(_ position: Int, expandSelection: Bool = false) {
    let originalCursor = cursor
    cursor = min(max(0, position), text.count)
    updateSelectionAfterMove(expandSelection: expandSelection, originalCursor: originalCursor)
    clampViewOffset()
  }

  mutating func selectAll() {
    setSelection(0..<text.count)
  }

  mutating func selectWord(at index: Int) {
    guard !text.isEmpty else { return }
    let bounded = max(0, min(index, max(0, text.count - 1)))
    let range = wordRange(at: bounded)
    setSelection(range)
  }

  mutating func setSelection(_ range: Range<Int>) {
    let lower = max(0, min(range.lowerBound, text.count))
    let upper = max(lower, min(range.upperBound, text.count))
    if lower == upper {
      selection = nil
      selectionAnchor = nil
      cursor = upper
      clampViewOffset()
      return
    }
    selection = lower..<upper
    selectionAnchor = lower
    cursor = upper
    viewOffset = min(viewOffset, lower)
    clampViewOffset()
  }

  mutating func beginSelection(at index: Int) {
    let clamped = min(max(0, index), text.count)
    selectionAnchor = clamped
    selection = clamped..<clamped
    cursor = clamped
    clampViewOffset()
  }

  mutating func ensureCursorVisible() {
    clampViewOffset()
  }

  func wordRange(at index: Int) -> Range<Int> {
    if text.isEmpty { return 0..<0 }
    let maxIndex = max(0, text.count - 1)
    let clamped = max(0, min(index, maxIndex))
    let chars = Array(text)
    let target = chars[clamped]
    if target.isWhitespace {
      var start = clamped
      var end = clamped + 1
      var i = clamped - 1
      while i >= 0, chars[i].isWhitespace {
        start = i
        i -= 1
      }
      i = clamped + 1
      while i < chars.count, chars[i].isWhitespace {
        end = i + 1
        i += 1
      }
      return start..<end
    }
    if isWordCharacter(target) {
      var start = clamped
      var end = clamped + 1
      var i = clamped - 1
      while i >= 0, isWordCharacter(chars[i]) {
        start = i
        i -= 1
      }
      i = clamped + 1
      while i < chars.count, isWordCharacter(chars[i]) {
        end = i + 1
        i += 1
      }
      return start..<end
    }
    return clamped..<(clamped + 1)
  }

  mutating func clearSelection() {
    selection = nil
    selectionAnchor = nil
  }

  var hasSelection: Bool {
    if let range = selection { return !range.isEmpty }
    return false
  }

  private mutating func updateSelectionAfterMove(expandSelection: Bool, originalCursor: Int) {
    if expandSelection {
      if selectionAnchor == nil { selectionAnchor = originalCursor }
      if let anchor = selectionAnchor {
        if anchor == cursor {
          selection = nil
        } else if anchor < cursor {
          selection = anchor..<cursor
        } else {
          selection = cursor..<anchor
        }
      }
    } else {
      clearSelection()
    }
  }

  private mutating func removeSelectionIfNeeded() -> Bool {
    return deleteSelectionContents() != nil
  }

  private mutating func clampViewOffset() {
    viewOffset = min(max(0, viewOffset), max(0, text.count))
    if cursor < viewOffset { viewOffset = cursor }
    if viewOffset > cursor { viewOffset = cursor }
  }

  private func isWhitespace(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
  }

  private func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_"
  }

  private func wordBoundaryLeft(from position: Int) -> Int {
    guard position > 0 else { return 0 }
    var idx = position
    while idx > 0 {
      let currentChar = character(at: idx - 1)
      if !isWhitespace(currentChar) { break }
      idx -= 1
    }
    guard idx > 0 else { return 0 }
    let isWord = isWordCharacter(character(at: idx - 1))
    while idx > 0 {
      let nextChar = character(at: idx - 1)
      if isWhitespace(nextChar) { break }
      if isWordCharacter(nextChar) != isWord { break }
      idx -= 1
    }
    return idx
  }

  private func wordBoundaryRight(from position: Int) -> Int {
    guard position < text.count else { return text.count }
    var idx = position
    while idx < text.count {
      let currentChar = character(at: idx)
      if !isWhitespace(currentChar) { break }
      idx += 1
    }
    guard idx < text.count else { return text.count }
    let isWord = isWordCharacter(character(at: idx))
    while idx < text.count {
      let currentChar = character(at: idx)
      if isWhitespace(currentChar) { break }
      if isWordCharacter(currentChar) != isWord { break }
      idx += 1
    }
    return idx
  }

  private func character(at index: Int) -> Character {
    let stringIndex = text.index(text.startIndex, offsetBy: index)
    return text[stringIndex]
  }
}
