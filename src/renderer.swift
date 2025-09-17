import Foundation

func renderLineWithSelection(
  lineContent: String, lineIndex: Int, state: EditorState, contentWidth: Int, columnOffset: Int = 0,
  isEndOfLogicalLine: Bool = true
) -> String {
  var output = ""
  for (column, char) in lineContent.enumerated() {
    let isSelected = state.isPositionSelected(line: lineIndex, column: column + columnOffset)
    output += isSelected ? Terminal.highlight + String(char) + Terminal.reset : String(char)
  }
  if let startSel = state.selectionStart, let endSel = state.selectionEnd {
    let (start, end) = state.normalizeSelection(start: startSel, end: endSel)
    let fragmentStartColumn = columnOffset
    let fragmentEndColumn = columnOffset + lineContent.count
    var shouldExtend = false
    if let range = selectionRangeForLine(state: state, lineIndex: lineIndex) {
      let selectionCoversFragment = max(range.start, fragmentStartColumn) < min(range.end, fragmentEndColumn)
      let selectionContinuesSameLine = range.end > fragmentEndColumn
      let selectionContinuesNextLine = lineIndex < end.line
      let spansIntermediateLine = lineIndex > start.line && lineIndex < end.line
      let emptyLineSelected = lineContent.isEmpty && (
        spansIntermediateLine
          || (lineIndex == start.line && start.line != end.line)
          || (lineIndex == end.line && start.line != end.line && end.column > 0)
      )

      if selectionCoversFragment && (selectionContinuesSameLine || selectionContinuesNextLine) {
        shouldExtend = true
      } else if selectionCoversFragment, case .line = state.selectionMode {
        shouldExtend = true
      } else if emptyLineSelected {
        shouldExtend = true
      }
    }
    let visibleLen = lineContent.count
    let remaining = max(0, contentWidth - visibleLen)
    if remaining > 0 {
      output +=
        shouldExtend
        ? (Terminal.highlight + String(repeating: " ", count: remaining) + Terminal.reset)
        : String(repeating: " ", count: remaining)
    }
  }
  if !state.hasSelection {
    let visibleLen = lineContent.count
    let remaining = max(0, contentWidth - visibleLen)
    if remaining > 0 { output += String(repeating: " ", count: remaining) }
  }
  return output
}

func selectionRangeForLine(state: EditorState, lineIndex: Int) -> (start: Int, end: Int)? {
  guard let startSel = state.selectionStart, let endSel = state.selectionEnd else { return nil }
  let (start, end) = state.normalizeSelection(start: startSel, end: endSel)
  if lineIndex < start.line || lineIndex > end.line { return nil }
  let lineLen = state.buffer[lineIndex].count
  if start.line == end.line { return (start: start.column, end: end.column) }
  if lineIndex == start.line { return (start: start.column, end: lineLen) }
  if lineIndex == end.line { return (start: 0, end: end.column) }
  return (start: 0, end: lineLen)
}

func drawEditor(state: inout EditorState) {
  if state.buffer.isEmpty { state.buffer = [""] }
  state.clampCursor()
  let termSize = Terminal.getTerminalSize()
  print(Terminal.clearScreen + Terminal.home, terminator: "")

  let headerLines = 1
  let footerLines = 2
  let maxVisibleRows = termSize.rows - headerLines - footerLines
  let contentWidth = termSize.cols - 6
  let visualRows = buildVisualRows(state: state, contentWidth: max(1, contentWidth))
  let (cursorVIndex, cursorVRow) = findCursorVisualIndex(state: state, rows: visualRows)
  if state.pinCursorToView {
    if cursorVIndex < state.visualScrollOffset {
      state.visualScrollOffset = cursorVIndex
    } else if cursorVIndex >= state.visualScrollOffset + maxVisibleRows {
      state.visualScrollOffset = max(0, cursorVIndex - maxVisibleRows + 1)
    }
  }
  let vScroll = state.visualScrollOffset

  // Header
  let filename = state.displayFilename
  let termWidth = termSize.cols
  let decoratedName = " \(filename) "
  let availableWidth = max(0, termWidth - decoratedName.count)
  let leftCount = availableWidth / 2
  let rightCount = availableWidth - leftCount
  // Use a contiguous double-line box drawing glyph; triple-line glyphs like U+2261 introduce spacing.
  let barCharacter = "\u{2550}"
  let leftDecoration = leftCount > 0
    ? Terminal.grey + String(repeating: barCharacter, count: leftCount) + Terminal.reset
    : ""
  let rightDecoration = rightCount > 0
    ? Terminal.grey + String(repeating: barCharacter, count: rightCount) + Terminal.reset
    : ""
  let nameSegment = Terminal.bold + Terminal.green + decoratedName + Terminal.reset
  print(leftDecoration + nameSegment + rightDecoration)

  // Body
  let startV = max(0, min(vScroll, max(0, visualRows.count - 1)))
  let endV = min(visualRows.count, startV + maxVisibleRows)
  if startV < endV {
    for vi in startV..<endV {
      let vr = visualRows[vi]
      let lineNum = vr.lineIndex + 1
      let line = state.buffer[vr.lineIndex]
      let sliceStart = line.index(line.startIndex, offsetBy: vr.start)
      let sliceEnd = line.index(line.startIndex, offsetBy: vr.end)
      let fragment = String(line[sliceStart..<sliceEnd])
      if vr.isFirst {
        let isActiveLine = !state.hasSelection && vr.lineIndex == state.cursorLine
        let isSelectedLine = lineIsSelected(lineIndex: vr.lineIndex, state: state)
        let lineNumberColor = (isActiveLine || isSelectedLine) ? Terminal.pink : Terminal.grey
        print(lineNumberColor + String(format: "%4d", lineNum) + Terminal.reset + " ", terminator: "")
      } else {
        print(String(repeating: " ", count: 5), terminator: "")
      }
      // Scrollbar
      let totalRows = visualRows.count
      let trackHeight = maxVisibleRows
      let (handleStart, handleHeight, _) = Scrollbar.compute(
        totalRows: totalRows, trackHeight: trackHeight, offset: state.visualScrollOffset)
      let localRow = vi - startV
      let isHandle = handleHeight > 0 && localRow >= handleStart && localRow < handleStart + handleHeight
      let scrollbarChar = isHandle ? (Terminal.scrollbarBG + " " + Terminal.reset) : " "
      let lineOut =
        state.hasSelection
        ? renderLineWithSelection(
          lineContent: fragment, lineIndex: vr.lineIndex, state: state, contentWidth: contentWidth,
          columnOffset: vr.start, isEndOfLogicalLine: vr.isEndOfLine)
        : (fragment + String(repeating: " ", count: max(0, contentWidth - fragment.count)))
      print(lineOut + scrollbarChar)
    }
  }

  // Fill remaining rows
  let targetRows = startV + maxVisibleRows
  if endV < targetRows && endV < targetRows {
    let totalRows = visualRows.count
    let trackHeight = maxVisibleRows
    let (handleStart, handleHeight, _) = Scrollbar.compute(
      totalRows: totalRows, trackHeight: trackHeight, offset: state.visualScrollOffset)
    for i in endV..<targetRows {
      let localRow = i - startV
      let isHandle = handleHeight > 0 && localRow >= handleStart && localRow < handleStart + handleHeight
      let scrollbarChar = isHandle ? (Terminal.scrollbarBG + " " + Terminal.reset) : " "
      print(String(repeating: " ", count: 5), terminator: "")
      print(String(repeating: " ", count: contentWidth) + scrollbarChar)
    }
  }

  // Footer
  let status = makeStatusLine(state: state)
  let statusPadding = max(0, termWidth - status.text.count)
  let rightAlignedStatus = String(repeating: " ", count: statusPadding) + status.text
  print(status.color + rightAlignedStatus + Terminal.reset)

  // Place cursor only when it is within the visible text region
  let cursorVisibleInView =
    maxVisibleRows > 0 && cursorVIndex >= vScroll && cursorVIndex < vScroll + maxVisibleRows
  if cursorVisibleInView {
    let displayRow = 2 + (cursorVIndex - vScroll)
    let cursorColInRow = max(0, state.cursorColumn - cursorVRow.start)
    let displayCol = 6 + cursorColInRow
    print(Terminal.moveCursor(to: displayRow, col: displayCol), terminator: "")
    print(state.cursorVisible ? Terminal.showCursor : Terminal.hideCursor, terminator: "")
  } else {
    print(Terminal.hideCursor, terminator: "")
  }
  fflush(stdout)
}

private func makeStatusLine(state: EditorState) -> (text: String, color: String) {
  let currentLine = state.cursorLine + 1

  guard state.hasSelection, let startSel = state.selectionStart, let endSel = state.selectionEnd else {
    return ("Ln \(currentLine), Col \(state.cursorColumn + 1)", Terminal.grey)
  }

  let (start, end) = state.normalizeSelection(start: startSel, end: endSel)
  let lineCount = countSelectedLines(in: state, from: start, to: end)
  let characterCount = countSelectedCharacters(in: state, from: start, to: end)
  return ("Lns \(lineCount), Chars \(characterCount)", Terminal.grey)
}

private func countSelectedLines(in state: EditorState, from start: (line: Int, column: Int), to end: (line: Int, column: Int)) -> Int {
  if start.line == end.line { return 1 }
  return max(1, end.line - start.line + 1)
}

private func countSelectedCharacters(in state: EditorState, from start: (line: Int, column: Int), to end: (line: Int, column: Int)) -> Int {
  if start.line == end.line {
    return max(0, end.column - start.column)
  }

  var total = 0
  for lineIndex in start.line...end.line {
    if let range = selectionRangeForLine(state: state, lineIndex: lineIndex) {
      total += max(0, range.end - range.start)
    }
  }

  let newlineCount = max(0, countSelectedLines(in: state, from: start, to: end) - 1)
  return total + newlineCount
}

private func lineIsSelected(lineIndex: Int, state: EditorState) -> Bool {
  guard state.hasSelection, let startSel = state.selectionStart, let endSel = state.selectionEnd else {
    return false
  }
  let (start, end) = state.normalizeSelection(start: startSel, end: endSel)
  if start.line == end.line {
    guard start.column != end.column else { return false }
    return lineIndex == start.line
  }
  return lineIndex >= start.line && lineIndex <= end.line
}
