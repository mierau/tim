import Foundation

// Editing actions and text utilities

func insertCharacter(_ char: Character, state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state) }
  let line = state.buffer[state.cursorLine]
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  let afterCursor = String(line.dropFirst(safeColumn))
  state.buffer[state.cursorLine] = beforeCursor + String(char) + afterCursor
  state.cursorColumn += 1
}

func insertNewline(state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state) }
  let line = state.buffer[state.cursorLine]
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  let afterCursor = String(line.dropFirst(safeColumn))
  let baseIndentation = getIndentation(line: line)
  let newIndentation = getNewLineIndentation(line: line, baseIndentation: baseIndentation)
  state.buffer[state.cursorLine] = beforeCursor
  state.buffer.insert(newIndentation + afterCursor, at: state.cursorLine + 1)
  state.cursorLine += 1
  state.cursorColumn = newIndentation.count
  state.clampCursor()
}

func getIndentation(line: String) -> String {
  var indentation = ""
  for char in line {
    if char == " " || char == "\t" { indentation.append(char) } else { break }
  }
  return indentation
}

func getNewLineIndentation(line: String, baseIndentation: String) -> String {
  let trimmedLine = line.trimmingCharacters(in: .whitespaces)
  let blockKeywords = ["if", "loop", "for", "while", "func", "function", "unless", "else"]
  for keyword in blockKeywords {
    if trimmedLine.hasPrefix(keyword + " ") || trimmedLine == keyword {
      return baseIndentation + "  "
    }
  }
  if trimmedLine.hasSuffix("[") { return baseIndentation + "  " }
  if trimmedLine.hasSuffix(" then") || trimmedLine == "then" { return baseIndentation + "  " }
  if trimmedLine.hasSuffix(" do") || trimmedLine == "do" { return baseIndentation + "  " }
  return baseIndentation
}

func backspace(state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state); return }
  if state.cursorColumn > 0 {
    let line = state.buffer[state.cursorLine]
    let safeColumn = max(0, min(state.cursorColumn - 1, line.count))
    let safeCursorColumn = min(state.cursorColumn, line.count)
    let beforeCursor = String(line.prefix(safeColumn))
    let afterCursor = String(line.dropFirst(safeCursorColumn))
    state.buffer[state.cursorLine] = beforeCursor + afterCursor
    state.cursorColumn -= 1
  } else if state.cursorLine > 0 {
    let currentLine = state.buffer[state.cursorLine]
    let previousLine = state.buffer[state.cursorLine - 1]
    state.buffer[state.cursorLine - 1] = previousLine + currentLine
    state.buffer.remove(at: state.cursorLine)
    state.cursorLine -= 1
    state.cursorColumn = previousLine.count
  }
  state.clampCursor()
}

func insertTab(state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state) }
  insertCharacter(" ", state: &state)
  insertCharacter(" ", state: &state)
}

func forwardDelete(state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state); return }
  let line = state.buffer[state.cursorLine]
  if state.cursorColumn >= line.count {
    if state.cursorLine < state.buffer.count - 1 {
      let nextLine = state.buffer[state.cursorLine + 1]
      state.buffer[state.cursorLine] = line + nextLine
      state.buffer.remove(at: state.cursorLine + 1)
    }
    state.clampCursor(); return
  }
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  let afterCursor = String(line.dropFirst(safeColumn + 1))
  state.buffer[state.cursorLine] = beforeCursor + afterCursor
  state.clampCursor()
}

func smartDeleteBackward(state: inout EditorState) {
  if state.hasSelection { deleteSelection(state: &state); return }
  if state.cursorColumn == 0 {
    if state.cursorLine > 0 {
      let currentLine = state.buffer[state.cursorLine]
      let previousLine = state.buffer[state.cursorLine - 1]
      state.buffer[state.cursorLine - 1] = previousLine + currentLine
      state.buffer.remove(at: state.cursorLine)
      state.cursorLine -= 1
      state.cursorColumn = previousLine.count
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
  }
  state.clearSelection()
}

func selectAll(state: inout EditorState) {
  state.selectionStart = (0, 0)
  let lastLine = state.buffer.count - 1
  let lastColumn = state.buffer[lastLine].count
  state.selectionEnd = (lastLine, lastColumn)
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
  if state.hasSelection { deleteSelection(state: &state); return }
  let line = state.buffer[state.cursorLine]
  let safeColumn = min(state.cursorColumn, line.count)
  let beforeCursor = String(line.prefix(safeColumn))
  state.buffer[state.cursorLine] = beforeCursor
  state.clampCursor(); state.showCursor()
}

func jumpWordForward(state: inout EditorState) {
  jumpWordForwardInternal(state: &state, clearSelection: true)
}
func jumpWordBackward(state: inout EditorState) {
  jumpWordBackwardInternal(state: &state, clearSelection: true)
}

func jumpWordForwardInternal(state: inout EditorState, clearSelection: Bool) {
  if clearSelection { state.clearSelection() }
  let currentLine = state.buffer[state.cursorLine]
  if state.cursorColumn >= currentLine.count {
    if state.cursorLine < state.buffer.count - 1 { state.cursorLine += 1; state.cursorColumn = 0 }
    return
  }
  let afterCursor = String(currentLine.dropFirst(state.cursorColumn))
  let newPosition = findWordForwardPosition(text: afterCursor)
  state.cursorColumn += newPosition
  if state.cursorColumn >= currentLine.count {
    if state.cursorLine < state.buffer.count - 1 { state.cursorLine += 1; state.cursorColumn = 0 }
  }
  state.clampCursor(); state.showCursor()
}

func jumpWordBackwardInternal(state: inout EditorState, clearSelection: Bool) {
  if clearSelection { state.clearSelection() }
  if state.cursorColumn == 0 {
    if state.cursorLine > 0 {
      state.cursorLine -= 1; state.cursorColumn = state.buffer[state.cursorLine].count
    }
    return
  }
  let currentLine = state.buffer[state.cursorLine]
  let beforeCursor = String(currentLine.prefix(state.cursorColumn))
  let newPosition = findSmartDeletePosition(text: beforeCursor)
  state.cursorColumn = newPosition
  state.clampCursor(); state.showCursor()
}

func findWordForwardPosition(text: String) -> Int {
  if text.isEmpty { return 0 }
  let chars = Array(text)
  var pos = 0
  let startChar = chars[pos]
  if startChar.isWhitespace {
    while pos < chars.count && chars[pos].isWhitespace { pos += 1 }
  } else if startChar.isLetter || startChar.isNumber || startChar == "_" {
    while pos < chars.count && (chars[pos].isLetter || chars[pos].isNumber || chars[pos] == "_") {
      pos += 1
    }
  } else {
    while pos < chars.count && !chars[pos].isWhitespace && !chars[pos].isLetter
      && !chars[pos].isNumber && chars[pos] != "_"
    { pos += 1 }
  }
  while pos < chars.count && chars[pos].isWhitespace { pos += 1 }
  return pos
}

func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

func wordRange(in line: String, at column: Int) -> (start: Int, end: Int) {
  if line.isEmpty { return (0, 0) }
  let clampedColumn = max(0, min(column, line.count == 0 ? 0 : line.count - 1))
  let chars = Array(line)
  let targetChar = chars[clampedColumn]
  let isWord = isWordCharacter(targetChar)
  var start = clampedColumn
  var end = clampedColumn + 1
  var i = clampedColumn - 1
  while i >= 0 {
    let c = chars[i]
    if isWord {
      if isWordCharacter(c) { start = i; i -= 1; continue }
    } else {
      if !isWordCharacter(c) && !c.isWhitespace { start = i; i -= 1; continue }
      if targetChar.isWhitespace && c.isWhitespace { start = i; i -= 1; continue }
    }
    break
  }
  i = clampedColumn + 1
  while i < chars.count {
    let c = chars[i]
    if isWord {
      if isWordCharacter(c) { end = i + 1; i += 1; continue }
    } else {
      if !isWordCharacter(c) && !c.isWhitespace { end = i + 1; i += 1; continue }
      if targetChar.isWhitespace && c.isWhitespace { end = i + 1; i += 1; continue }
    }
    break
  }
  return (start, end)
}

