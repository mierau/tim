import Foundation

private let undoCoalescingInterval: TimeInterval = 0.5
private let undoStackLimit = 100

// Editing actions and text utilities

func insertCharacter(_ char: Character, state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .insert)
  if state.hasSelection { deleteSelection(state: &state) }
  let lineIndex = state.cursorLine
  let line = state.buffer[lineIndex]
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  let afterCursor = String(line.dropFirst(safeColumn))
  let insertion = String(char)
  state.buffer[lineIndex] = beforeCursor + insertion + afterCursor
  state.cursorColumn = safeColumn + insertion.count
  state.bufferDidChange(lineRange: lineIndex..<(lineIndex + 1))
}

func insertNewline(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .insert)
  if state.hasSelection { deleteSelection(state: &state) }
  let currentLineIndex = state.cursorLine
  let line = state.buffer[currentLineIndex]
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  let afterCursor = String(line.dropFirst(safeColumn))
  let baseIndentation = getIndentation(line: line)
  let newIndentation = baseIndentation
  state.buffer[currentLineIndex] = beforeCursor
  state.buffer.insert(newIndentation + afterCursor, at: currentLineIndex + 1)
  state.cursorLine = currentLineIndex + 1
  state.cursorColumn = newIndentation.count
  state.clampCursor()
  let rangeEnd = min(state.buffer.count, currentLineIndex + 2)
  state.bufferDidChange(lineRange: currentLineIndex..<rangeEnd)
}

func getIndentation(line: String) -> String {
  var indentation = ""
  for char in line {
    if char == " " || char == "\t" { indentation.append(char) } else { break }
  }
  return indentation
}

func backspace(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .deleteBackward)
  if state.hasSelection { deleteSelection(state: &state); return }
  if state.cursorColumn > 0 {
    let line = state.buffer[state.cursorLine]
    let safeColumn = max(0, min(state.cursorColumn - 1, line.count))
    let safeCursorColumn = min(state.cursorColumn, line.count)
    let beforeCursor = String(line.prefix(safeColumn))
    let afterCursor = String(line.dropFirst(safeCursorColumn))
    state.buffer[state.cursorLine] = beforeCursor + afterCursor
    state.cursorColumn -= 1
    state.bufferDidChange(lineRange: state.cursorLine..<(state.cursorLine + 1))
  } else if state.cursorLine > 0 {
    let currentLine = state.buffer[state.cursorLine]
    let previousLine = state.buffer[state.cursorLine - 1]
    state.buffer[state.cursorLine - 1] = previousLine + currentLine
    state.buffer.remove(at: state.cursorLine)
    state.cursorLine -= 1
    state.cursorColumn = previousLine.count
    state.bufferDidChange(lineRange: state.cursorLine..<state.buffer.count)
  }
  state.clampCursor()
}

func insertTab(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .insert)
  if state.hasSelection { deleteSelection(state: &state) }
  insertCharacter(" ", state: &state)
  insertCharacter(" ", state: &state)
}

func forwardDelete(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .deleteForward)
  if state.hasSelection { deleteSelection(state: &state); return }
  let line = state.buffer[state.cursorLine]
  if state.cursorColumn >= line.count {
    if state.cursorLine < state.buffer.count - 1 {
      let nextLine = state.buffer[state.cursorLine + 1]
      state.buffer[state.cursorLine] = line + nextLine
      state.buffer.remove(at: state.cursorLine + 1)
      state.bufferDidChange(lineRange: state.cursorLine..<state.buffer.count)
    }
    state.clampCursor(); return
  }
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  let afterCursor = String(line.dropFirst(safeColumn + 1))
  state.buffer[state.cursorLine] = beforeCursor + afterCursor
  state.clampCursor()
  state.bufferDidChange(lineRange: state.cursorLine..<(state.cursorLine + 1))
}

func smartDeleteBackward(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .deleteBackward)
  if state.hasSelection { deleteSelection(state: &state); return }
  if state.cursorColumn == 0 {
    if state.cursorLine > 0 {
      let currentLine = state.buffer[state.cursorLine]
      let previousLine = state.buffer[state.cursorLine - 1]
      state.buffer[state.cursorLine - 1] = previousLine + currentLine
      state.buffer.remove(at: state.cursorLine)
      state.cursorLine -= 1
      state.cursorColumn = previousLine.count
      state.bufferDidChange(lineRange: state.cursorLine..<state.buffer.count)
    }
    state.clampCursor(); return
  }
  let line = state.buffer[state.cursorLine]
  let beforeCursor = String(line.prefix(state.cursorColumn))
  let deleteToPosition = findSmartDeletePosition(text: beforeCursor)
  let afterCursor = String(line.dropFirst(state.cursorColumn))
  state.buffer[state.cursorLine] = String(beforeCursor.prefix(deleteToPosition)) + afterCursor
  state.cursorColumn = deleteToPosition
  state.clampCursor()
  state.bufferDidChange(lineRange: state.cursorLine..<(state.cursorLine + 1))
}

func findSmartDeletePosition(text: String) -> Int {
  if text.isEmpty { return 0 }
  let chars = Array(text)
  var pos = chars.count - 1
  // Skip initial whitespace
  while pos >= 0 && chars[pos].isWhitespace { pos -= 1 }
  if pos < 0 { return 0 }
  let currentChar = chars[pos]
  if currentChar.isLetter || currentChar.isNumber || currentChar == "_" {
    while pos >= 0, (chars[pos].isLetter || chars[pos].isNumber || chars[pos] == "_") { pos -= 1 }
    pos += 1
  } else {
    while pos >= 0,
      (!chars[pos].isLetter && !chars[pos].isNumber && chars[pos] != "_"
        && !chars[pos].isWhitespace)
    { pos -= 1 }
    pos += 1
  }
  return max(0, pos)
}

func deleteSelection(state: inout EditorState) {
  guard let start = state.selectionStart, let end = state.selectionEnd else { return }
  let (startPos, endPos) = state.normalizeSelection(start: start, end: end)
  if startPos.line == endPos.line {
    let line = state.buffer[startPos.line]
    let safeStartColumn = min(startPos.column, line.count)
    let safeEndColumn = min(endPos.column, line.count)
    let beforeSelection = String(line.prefix(safeStartColumn))
    let afterSelection = String(line.dropFirst(safeEndColumn))
    state.buffer[startPos.line] = beforeSelection + afterSelection
    state.cursorLine = startPos.line
    state.cursorColumn = safeStartColumn
    state.bufferDidChange(lineRange: startPos.line..<(startPos.line + 1))
  } else {
    let firstLine = state.buffer[startPos.line]
    let lastLine = state.buffer[endPos.line]
    let safeStartColumn = min(startPos.column, firstLine.count)
    let safeEndColumn = min(endPos.column, lastLine.count)
    let beforeSelection = String(firstLine.prefix(safeStartColumn))
    let afterSelection = String(lastLine.dropFirst(safeEndColumn))
    state.buffer[startPos.line] = beforeSelection + afterSelection
    if endPos.line > startPos.line {
      state.buffer.removeSubrange((startPos.line + 1)...endPos.line)
    }
    state.cursorLine = startPos.line
    state.cursorColumn = beforeSelection.count
    state.bufferDidChange(lineRange: startPos.line..<state.buffer.count)
  }
  state.clearSelection()
}

func selectAll(state: inout EditorState) {
  state.selectionStart = (0, 0)
  let lastLine = state.buffer.count - 1
  let lastColumn = state.buffer[lastLine].count
  state.selectionEnd = (lastLine, lastColumn)
}

func copySelection(state: inout EditorState) {
  guard state.hasSelection, let selection = selectedText(from: state) else { return }
  do {
    try Clipboard.copy(selection)
  } catch {
    fputs("Copy failed: \(error)\n", stderr)
  }
}

func cutSelection(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .other)
  guard state.hasSelection, let selection = selectedText(from: state) else { return }
  do {
    try Clipboard.copy(selection)
    deleteSelection(state: &state)
  } catch {
    fputs("Cut failed: \(error)\n", stderr)
  }
}

func pasteClipboard(state: inout EditorState) {
  do {
    recordUndoSnapshot(state: &state, operation: .paste)
    guard let pasted = try Clipboard.paste() else { return }
    if pasted.isEmpty { return }
    insertText(pasted, state: &state)
  } catch {
    fputs("Paste failed: \(error)\n", stderr)
  }
}

func selectLineUp(state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  if state.cursorLine > 0 {
    state.cursorLine -= 1
    let targetLineLength = state.buffer[state.cursorLine].count
    state.cursorColumn = min(state.cursorColumn, targetLineLength)
  }
  state.updateSelection(); state.showCursor()
}

func selectLineDown(state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  if state.cursorLine < state.buffer.count - 1 {
    state.cursorLine += 1
    let targetLineLength = state.buffer[state.cursorLine].count
    state.cursorColumn = min(state.cursorColumn, targetLineLength)
  }
  state.updateSelection(); state.showCursor()
}

func moveToBeginningOfLine(state: inout EditorState) {
  state.clearSelection(); state.cursorColumn = 0; state.showCursor()
}

func moveToEndOfLine(state: inout EditorState) {
  state.clearSelection(); state.cursorColumn = state.buffer[state.cursorLine].count;
  state.showCursor()
}

func deleteToEndOfLine(state: inout EditorState) {
  recordUndoSnapshot(state: &state, operation: .other)
  if state.hasSelection { deleteSelection(state: &state); return }
  let line = state.buffer[state.cursorLine]
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  state.buffer[state.cursorLine] = beforeCursor
  state.clampCursor(); state.showCursor()
  state.bufferDidChange()
}

func jumpWordForward(state: inout EditorState) {
  state.clearSelection()
  moveCursorForwardByWord(state: &state)
}
func jumpWordBackward(state: inout EditorState) {
  state.clearSelection()
  moveCursorBackwardByWord(state: &state)
}

func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

func wordRange(in line: String, at column: Int) -> (start: Int, end: Int) {
  if line.isEmpty { return (0, 0) }
  let clampedColumn = max(0, min(column, line.count == 0 ? 0 : line.count - 1))
  let chars = Array(line)
  let targetChar = chars[clampedColumn]
  let isWord = isWordCharacter(targetChar)
  if targetChar.isWhitespace {
    var start = clampedColumn
    var end = clampedColumn + 1
    var i = clampedColumn - 1
    while i >= 0, chars[i].isWhitespace {
      start = i
      i -= 1
    }
    i = clampedColumn + 1
    while i < chars.count, chars[i].isWhitespace {
      end = i + 1
      i += 1
    }
    return (start, end)
  }

  if isWord {
    var start = clampedColumn
    var end = clampedColumn + 1
    var i = clampedColumn - 1
    while i >= 0, isWordCharacter(chars[i]) {
      start = i
      i -= 1
    }
    i = clampedColumn + 1
    while i < chars.count, isWordCharacter(chars[i]) {
      end = i + 1
      i += 1
    }
    return (start, end)
  }

  // Symbols and punctuation: select only the clicked character
  return (clampedColumn, clampedColumn + 1)
}

func moveCursorForwardByWord(state: inout EditorState) {
  var madeProgress = false
  outer: while state.cursorLine < state.buffer.count {
    let line = state.buffer[state.cursorLine]
    if state.cursorColumn >= line.count {
      if state.cursorLine < state.buffer.count - 1 {
        state.cursorLine += 1
        state.cursorColumn = 0
        madeProgress = true
        continue
      }
      break
    }

    let chars = Array(line)
    var index = state.cursorColumn
    let currentChar = chars[index]

    if currentChar.isWhitespace {
      while index < chars.count && chars[index].isWhitespace { index += 1 }
      madeProgress = madeProgress || index != state.cursorColumn
      state.cursorColumn = index
      continue
    }

    if isWordCharacter(currentChar) {
      while index < chars.count && isWordCharacter(chars[index]) { index += 1 }
    } else {
      while index < chars.count && !chars[index].isWhitespace && !isWordCharacter(chars[index]) {
        index += 1
      }
    }

    madeProgress = madeProgress || index != state.cursorColumn
    state.cursorColumn = index
    break outer
  }

  if madeProgress {
    state.clampCursor()
    state.showCursor()
  }
}

func moveCursorBackwardByWord(state: inout EditorState) {
  var madeProgress = false
  outer: while state.cursorLine >= 0 {
    if state.cursorColumn == 0 {
      if state.cursorLine > 0 {
        state.cursorLine -= 1
        state.cursorColumn = state.buffer[state.cursorLine].count
        madeProgress = true
        continue
      }
      break
    }

    let line = state.buffer[state.cursorLine]
    let chars = Array(line)
    var index = state.cursorColumn - 1
    let currentChar = chars[index]

    if currentChar.isWhitespace {
      while index >= 0 && chars[index].isWhitespace { index -= 1 }
      madeProgress = true
      state.cursorColumn = max(index + 1, 0)
      continue
    }

    if isWordCharacter(currentChar) {
      while index >= 0 && isWordCharacter(chars[index]) { index -= 1 }
    } else {
      while index >= 0 && !chars[index].isWhitespace && !isWordCharacter(chars[index]) {
        index -= 1
      }
    }

    madeProgress = true
    state.cursorColumn = index + 1
    break outer
  }

  if madeProgress {
    state.clampCursor()
    state.showCursor()
  }
}

private func selectedText(from state: EditorState) -> String? {
  guard let startSel = state.selectionStart, let endSel = state.selectionEnd else { return nil }
  let (start, end) = state.normalizeSelection(start: startSel, end: endSel)

  let startLine = start.line
  let endLine = end.line
  guard startLine >= 0, endLine < state.buffer.count else { return nil }

  if startLine == endLine {
    let line = state.buffer[startLine]
    let startColumn = min(start.column, line.count)
    let endColumn = min(end.column, line.count)
    if startColumn >= endColumn { return nil }
    let startIndex = line.index(line.startIndex, offsetBy: startColumn)
    let endIndex = line.index(line.startIndex, offsetBy: endColumn)
    return String(line[startIndex..<endIndex])
  }

  var segments: [String] = []
  let firstLine = state.buffer[startLine]
  let firstStartIndex = firstLine.index(firstLine.startIndex, offsetBy: min(start.column, firstLine.count))
  segments.append(String(firstLine[firstStartIndex...]))

  if endLine - startLine > 1 {
    for lineIndex in (startLine + 1)..<endLine {
      segments.append(state.buffer[lineIndex])
    }
  }

  let lastLine = state.buffer[endLine]
  let lastEndIndex = lastLine.index(lastLine.startIndex, offsetBy: min(end.column, lastLine.count))
  segments.append(String(lastLine[..<lastEndIndex]))

  return segments.joined(separator: "\n")
}

private func insertText(_ text: String, state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state) }

  let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
  let fragments = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

  guard !fragments.isEmpty else { return }

  let currentLine = state.buffer[state.cursorLine]
  let safeColumn = min(state.cursorColumn, currentLine.count)
  let beforeCursor = String(currentLine.prefix(safeColumn))
  let afterCursor = String(currentLine.dropFirst(safeColumn))

  if fragments.count == 1 {
    state.buffer[state.cursorLine] = beforeCursor + fragments[0] + afterCursor
    state.cursorColumn = beforeCursor.count + fragments[0].count
  } else {
    state.buffer[state.cursorLine] = beforeCursor + fragments[0]
    var insertIndex = state.cursorLine + 1
    if fragments.count > 2 {
      for fragment in fragments[1..<(fragments.count - 1)] {
        state.buffer.insert(String(fragment), at: insertIndex)
        insertIndex += 1
      }
    }
    let lastFragment = fragments.last ?? ""
    state.buffer.insert(lastFragment + afterCursor, at: insertIndex)
    state.cursorLine = insertIndex
    state.cursorColumn = lastFragment.count
  }

  state.clampCursor()
  state.showCursor()
  state.bufferDidChange()
}

func saveDocument(state: inout EditorState) {
  let defaultFileName = "untitled.txt"
  let resolvedPath: String
  if let existing = state.filePath, !existing.isEmpty {
    resolvedPath = existing
  } else {
    let cwd = FileManager.default.currentDirectoryPath
    resolvedPath = (cwd as NSString).appendingPathComponent(defaultFileName)
    state.filePath = resolvedPath
  }

  let expandedPath = (resolvedPath as NSString).expandingTildeInPath
  let fileURL = URL(fileURLWithPath: expandedPath)
  let directoryURL = fileURL.deletingLastPathComponent()

  do {
    let directoryPath = directoryURL.path
    if !directoryPath.isEmpty && directoryPath != "." {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    let contents = state.buffer.joined(separator: "\n")
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    state.filePath = expandedPath
    state.savedBuffer = state.buffer
    state.bufferDidChange()
    state.needsRedraw = true
  } catch {
    fputs("Failed to save file: \(expandedPath) (\(error))\n", stderr)
  }
}

func undo(state: inout EditorState) {
  guard let snapshot = state.undoStack.popLast() else { return }
  let redoSnapshot = UndoSnapshot(state: state)
  state.redoStack.append(redoSnapshot)
  snapshot.apply(to: &state)
  state.lastUndoOperation = nil
  state.lastUndoTimestamp = nil
}

func redo(state: inout EditorState) {
  guard let snapshot = state.redoStack.popLast() else { return }
  let undoSnapshot = UndoSnapshot(state: state)
  state.undoStack.append(undoSnapshot)
  snapshot.apply(to: &state)
  state.lastUndoOperation = nil
  state.lastUndoTimestamp = nil
}

private func recordUndoSnapshot(state: inout EditorState, operation: UndoOperationKind) {
  let now = Date()
  let canCoalesce = operation.coalesces
    && state.lastUndoOperation == operation
    && now.timeIntervalSince(state.lastUndoTimestamp ?? Date.distantPast) < undoCoalescingInterval
  if !canCoalesce {
    let snapshot = UndoSnapshot(state: state)
    state.undoStack.append(snapshot)
    if state.undoStack.count > undoStackLimit {
      state.undoStack.removeFirst(state.undoStack.count - undoStackLimit)
    }
    state.redoStack.removeAll()
  } else {
    state.redoStack.removeAll()
  }
  state.lastUndoOperation = operation
  state.lastUndoTimestamp = now
}
