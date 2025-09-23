import Foundation

private struct FindFieldRenderResult {
  let statusText: String
  let statusWidth: Int
  let caretOffset: Int
  let layout: EditorState.FindState.FindFieldLayout
}

/// Builds the find prompt status line and associated layout metadata for the footer.
/// - Parameters:
///   - state: Mutable editor state (updates view offset on the find field).
///   - maxWidth: Maximum display width reserved for the status portion (excluding control hints).
///   - statusColumnBase: The 1-based terminal column where the status text begins.
///   - baseColor: ANSI color prefix applied to non-selected characters in the field.
/// - Returns: The rendered status string plus layout details for hit-testing and cursor placement.
private func buildFindStatus(
  state: inout EditorState, maxWidth: Int, statusColumnBase: Int, baseColor: String
) -> FindFieldRenderResult
{
  let prefix = "Find: "
  let prefixWidth = Terminal.displayWidth(of: prefix)
  let fieldWidth = max(1, maxWidth - prefixWidth)

  let characters = Array(state.find.field.text)
  let widths = characters.map { max(1, Terminal.displayWidth(of: $0)) }
  let cursor = min(max(0, state.find.field.cursor), characters.count)

  var viewOffset = min(max(0, state.find.field.viewOffset), characters.count)
  if cursor < viewOffset { viewOffset = cursor }

  func widthBetween(_ start: Int, _ end: Int) -> Int {
    guard start < end else { return 0 }
    var total = 0
    for idx in start..<end { total += widths[idx] }
    return total
  }

  while viewOffset > 0 && widthBetween(viewOffset, cursor) > fieldWidth {
    viewOffset -= 1
  }
  while widthBetween(viewOffset, cursor) > fieldWidth && viewOffset < cursor {
    viewOffset += 1
  }

  var visibleEnd = viewOffset
  var usedWidth = 0
  while visibleEnd < characters.count {
    let nextWidth = widths[visibleEnd]
    if usedWidth + nextWidth > fieldWidth {
      if usedWidth == 0 {
        usedWidth += nextWidth
        visibleEnd += 1
      }
      break
    }
    usedWidth += nextWidth
    visibleEnd += 1
  }

  state.find.field.viewOffset = viewOffset

  let selection = state.find.field.selection
  var statusText = Terminal.grey + prefix + Terminal.white
  var columns: [EditorState.FindState.FindFieldLayout.Column] = []
  var columnPosition = prefixWidth

  for idx in viewOffset..<visibleEnd {
    let character = characters[idx]
    let width = widths[idx]
    let charString = String(character)
    if selection?.contains(idx) ?? false {
      statusText += Terminal.highlight + charString + Terminal.reset + Terminal.white
    } else {
      statusText += charString
    }
    let absoluteRange = (statusColumnBase + columnPosition)..<(statusColumnBase + columnPosition + width)
    columns.append(.init(index: idx, columnRange: absoluteRange))
    columnPosition += width
  }

  statusText += Terminal.reset

  let caretOffset = prefixWidth + widthBetween(viewOffset, cursor)
  let statusWidth = prefixWidth + usedWidth
  let fieldStartColumn = statusColumnBase + prefixWidth
  let fieldEndColumn = statusColumnBase + columnPosition

  let trailingRange = fieldEndColumn..<(fieldEndColumn + 1)
  columns.append(.init(index: visibleEnd, columnRange: trailingRange))

  let layout = EditorState.FindState.FindFieldLayout(
    fieldStartColumn: fieldStartColumn,
    fieldEndColumn: trailingRange.upperBound,
    clickableFieldEndColumn: trailingRange.upperBound,
    caretColumn: statusColumnBase + caretOffset,
    columns: columns)

  return FindFieldRenderResult(
    statusText: statusText,
    statusWidth: statusWidth,
    caretOffset: caretOffset,
    layout: layout)
}

/// Renders a single visual row, applying selection and find-match highlighting.
/// - Parameters:
///   - lineContent: The substring of the logical line visible on this row.
///   - lineIndex: Logical line index in the buffer.
///   - state: Current editor state (used to consult selections, matches, etc.).
///   - contentWidth: Width allocated for editor text (excluding gutter/scrollbar).
///   - columnOffset: Logical column where this fragment begins.
///   - isEndOfLogicalLine: Indicates whether this row terminates the underlying logical line.
///   - highlightRanges: Optional ranges to highlight for find matches (columns relative to logical line).
///   - highlightStyle: ANSI styling applied to the highlight ranges.
/// - Returns: A rendered string ready to print for this row (excluding gutter and scrollbar).
func renderLineWithSelection(
  lineContent: String, lineIndex: Int, state: EditorState, contentWidth: Int, columnOffset: Int = 0,
  isEndOfLogicalLine: Bool = true, highlightRanges: [Range<Int>] = [], highlightStyle: String? = nil
) -> String {
  var output = ""
  let logicalLineLength = state.buffer[lineIndex].count
  var renderedWidth = 0
  var columnIndex = 0
  let sortedHighlights = highlightRanges.sorted { $0.lowerBound < $1.lowerBound }
  var highlightIndex = 0
  for char in lineContent {
    let isSelected = state.isPositionSelected(line: lineIndex, column: columnIndex + columnOffset)
    let charString = String(char)
    let globalColumn = columnIndex + columnOffset
    var isFindHighlighted = false
    while highlightIndex < sortedHighlights.count && sortedHighlights[highlightIndex].upperBound <= globalColumn {
      highlightIndex += 1
    }
    if highlightIndex < sortedHighlights.count && sortedHighlights[highlightIndex].contains(globalColumn) {
      isFindHighlighted = true
    }
    if isSelected {
      output += Terminal.highlight + charString + Terminal.reset
    } else if isFindHighlighted, let style = highlightStyle {
      output += style + charString + Terminal.reset
    } else {
      output += charString
    }
    renderedWidth += Terminal.displayWidth(of: char)
    columnIndex += 1
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

      if selectionCoversFragment {
        if selectionContinuesSameLine || selectionContinuesNextLine || spansIntermediateLine {
          shouldExtend = true
        }
        if case .line = state.selectionMode { shouldExtend = true }
        if isEndOfLogicalLine,
          fragmentEndColumn == logicalLineLength,
          range.end > logicalLineLength
        {
          shouldExtend = true
        }
      }

      if !shouldExtend,
        isEndOfLogicalLine,
        fragmentEndColumn == logicalLineLength,
        range.start == logicalLineLength,
        range.end > logicalLineLength
      {
        shouldExtend = true
      }

      if !shouldExtend,
        isEndOfLogicalLine,
        lineIndex == start.line,
        lineIndex < end.line,
        start.column >= logicalLineLength
      {
        shouldExtend = true
      }

      if emptyLineSelected { shouldExtend = true }
    }
    let remaining = max(0, contentWidth - renderedWidth)
    if remaining > 0 {
      output +=
        shouldExtend
        ? (Terminal.highlight + String(repeating: " ", count: remaining) + Terminal.reset)
        : String(repeating: " ", count: remaining)
    }
  }
  if !state.hasSelection {
    let remaining = max(0, contentWidth - renderedWidth)
    if remaining > 0 { output += String(repeating: " ", count: remaining) }
  }
  return output
}

/// Computes the selection span intersecting a specific line.
/// - Parameters:
///   - state: Editor state containing the active selection.
///   - lineIndex: The logical line index to inspect.
/// - Returns: A tuple describing the selected column range, or `nil` when not selected.
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

/// Renders the entire editor view, diffing against the previous frame to minimize redraw.
/// - Parameter state: Mutable editor state containing layout/cache information and prior frame data.
func drawEditor(state: inout EditorState) {
  if state.buffer.isEmpty { state.buffer = [""] }
  state.clampCursor()

  let termSize = Terminal.getTerminalSize()
  let termRows = max(1, termSize.rows)
  let termWidth = max(1, termSize.cols)

  let headerLines = 1
  let footerLines = 2
  let maxVisibleRows = max(0, termRows - headerLines - footerLines)
  let gutterWidth = state.showLineNumbers ? 5 : 1
  let contentWidth = max(1, termWidth - (gutterWidth + 1))
  let layoutWidth = contentWidth

  var frame = Array(repeating: String(repeating: " ", count: termWidth), count: termRows)

  var layoutSnapshot = state.layoutCache.snapshot(for: state, contentWidth: layoutWidth)
  var visualRows = layoutSnapshot.rows
  if visualRows.isEmpty {
    let fallbackLine = min(state.cursorLine, max(0, state.buffer.count - 1))
    visualRows = [VisualRow(lineIndex: fallbackLine, start: 0, end: 0, isFirst: true, isEndOfLine: true)]
  }
  let totalRows = max(visualRows.count, 1)

  if state.isDragging && state.dragAutoscrollDirection != 0 {
    let direction = state.dragAutoscrollDirection
    let headerLines = 1
    let footerLines = 2
    let maxVisibleRows = max(1, termRows - headerLines - footerLines)
    var newOffset = state.visualScrollOffset + direction
    let maxOffset = max(0, totalRows - maxVisibleRows)
    newOffset = max(0, min(maxOffset, newOffset))
    if newOffset != state.visualScrollOffset {
      state.visualScrollOffset = newOffset
      state.pinCursorToView = true
      layoutSnapshot = state.layoutCache.snapshot(for: state, contentWidth: layoutWidth)
      visualRows = layoutSnapshot.rows
    }

    if !visualRows.isEmpty {
      let visibleTop = state.visualScrollOffset
      let visibleBottom = min(totalRows - 1, visibleTop + max(0, maxVisibleRows - 1))
      let targetIndex = direction < 0 ? visibleTop : visibleBottom
      let clampedIndex = max(0, min(targetIndex, visualRows.count - 1))
      let row = visualRows[clampedIndex]
      let line = state.buffer[row.lineIndex]
      let preferredColumn = max(0, state.dragSelectionPreferredColumn)
      let targetColumn = min(preferredColumn, line.count)
      state.updateSelectionDuringDrag(targetLine: row.lineIndex, targetColumn: targetColumn)
    }
  } else if !state.isDragging {
    state.dragAutoscrollDirection = 0
  }

  var maxOffsetActual = max(0, totalRows - maxVisibleRows)
  if state.visualScrollOffset > maxOffsetActual {
    state.visualScrollOffset = maxOffsetActual
  }

  var vScroll = state.visualScrollOffset

  let (cursorVIndex, cursorVRow) = findCursorVisualIndex(state: state, snapshot: layoutSnapshot)
  if state.pinCursorToView {
    if cursorVIndex < state.visualScrollOffset {
      state.visualScrollOffset = cursorVIndex
    } else if cursorVIndex >= state.visualScrollOffset + maxVisibleRows {
      state.visualScrollOffset = max(0, cursorVIndex - maxVisibleRows + 1)
    }
    vScroll = state.visualScrollOffset
  }

  maxOffsetActual = max(0, totalRows - maxVisibleRows)
  if vScroll > maxOffsetActual {
    vScroll = maxOffsetActual
    state.visualScrollOffset = vScroll
  }

  // Header
  let filename = state.displayFilename
  let spaceAroundTitle = 1
  let indicatorText = state.isDirty ? "• " : ""
  let indicatorVisibleWidth = Terminal.displayWidth(of: indicatorText)
  let displayWidth =
    2 * spaceAroundTitle + indicatorVisibleWidth + Terminal.displayWidth(of: filename)
  let availableWidth = max(0, termWidth - displayWidth)
  let leftCount = availableWidth / 2
  let rightCount = availableWidth - leftCount
  let barCharacter = "\u{2550}"
  let indicatorStyled = state.isDirty ? "\(Terminal.white)•\(Terminal.reset) " : ""
  let decoratedDisplay = String(repeating: " ", count: spaceAroundTitle)
    + indicatorStyled + Terminal.bold + filename + Terminal.reset
    + String(repeating: " ", count: spaceAroundTitle)
  let leftDecoration = leftCount > 0
    ? Terminal.grey + String(repeating: barCharacter, count: leftCount) + Terminal.reset
    : ""
  let rightDecoration = rightCount > 0
    ? Terminal.grey + String(repeating: barCharacter, count: rightCount) + Terminal.reset
    : ""
  let headerLine = leftDecoration + decoratedDisplay + rightDecoration
  if termRows > 0 { frame[0] = headerLine }

  // Body rows (visible content + filler)
  let startV = max(0, min(vScroll, max(0, totalRows - 1)))
  let endV = min(totalRows, startV + maxVisibleRows)
  let bodyStartIndex = headerLines
  let bodyEndLimit = max(bodyStartIndex, min(termRows - footerLines, termRows))
  var bodyRowIndex = bodyStartIndex

  if startV < endV && bodyRowIndex < bodyEndLimit {
    for vi in startV..<endV {
      if bodyRowIndex >= bodyEndLimit { break }
      let vr = visualRows[vi]
      let lineNum = vr.lineIndex + 1
      let line = state.buffer[vr.lineIndex]
      let sliceStart = line.index(line.startIndex, offsetBy: vr.start)
      let sliceEnd = line.index(line.startIndex, offsetBy: vr.end)
      let fragment = String(line[sliceStart..<sliceEnd])

      let gutter: String
      if state.showLineNumbers {
        if vr.isFirst {
          let isActiveLine = !state.hasSelection && vr.lineIndex == state.cursorLine
          let isSelectedLine = lineIsSelected(lineIndex: vr.lineIndex, state: state)
          let colorPrefix = (isActiveLine || isSelectedLine)
            ? Terminal.bold + Terminal.ansiBlue209
            : Terminal.grey
          gutter = colorPrefix + String(format: "%4d", lineNum) + Terminal.reset + " "
        } else {
          gutter = String(repeating: " ", count: gutterWidth)
        }
      } else {
        gutter = String(repeating: " ", count: gutterWidth)
      }

      let trackHeight = maxVisibleRows
      let (handleStart, handleHeight, _) = Scrollbar.compute(
        totalRows: totalRows, trackHeight: trackHeight, offset: state.visualScrollOffset)
      let localRow = vi - startV
      let isHandle = handleHeight > 0 && localRow >= handleStart && localRow < handleStart + handleHeight
      let scrollbarChar = isHandle ? (Terminal.scrollbarBG + " " + Terminal.reset) : " "

      var matchHighlights: [Range<Int>] = []
      var highlightStyle: String? = nil
      if state.find.active, state.focusedControl == .findField, !state.find.field.text.isEmpty {
        matchHighlights = state.find.matches.enumerated().compactMap { index, match in
          guard match.line == vr.lineIndex, index != state.find.currentIndex else { return nil }
          return match.range
        }
        if !matchHighlights.isEmpty {
          highlightStyle = Terminal.bold + Terminal.ansiBlue209
        }
      }

      let lineOut = renderLineWithSelection(
        lineContent: fragment, lineIndex: vr.lineIndex, state: state, contentWidth: contentWidth,
        columnOffset: vr.start, isEndOfLogicalLine: vr.isEndOfLine, highlightRanges: matchHighlights,
        highlightStyle: highlightStyle)

      frame[bodyRowIndex] = gutter + lineOut + scrollbarChar
      bodyRowIndex += 1
    }
  }

  if bodyRowIndex < bodyEndLimit {
    let gutterFiller = String(repeating: " ", count: gutterWidth)
    let filler = gutterFiller + String(repeating: " ", count: contentWidth) + " "
    for row in bodyRowIndex..<bodyEndLimit {
      frame[row] = filler
    }
  }

  if termRows >= 2 {
    frame[termRows - 2] = Terminal.reset + String(repeating: " ", count: termWidth)
  }

  // Footer preparation
  var controlHints: String
  var controlHintsLength: Int
  var statusText: String
  var statusColor: String
  var statusDisplayWidth: Int
  var pendingFindLayout: EditorState.FindState.FindFieldLayout? = nil

  if state.find.active {
    statusText = ""
    statusDisplayWidth = 0
    statusColor = Terminal.grey
    struct HintSegment {
      let plain: String
      let rendered: String
      let width: Int
    }

    func makeSegment(plain: String, rendered: String) -> HintSegment {
      HintSegment(plain: plain, rendered: rendered, width: Terminal.displayWidth(of: plain))
    }

    func totalWidth(of segments: [HintSegment], separatorWidth: Int) -> Int {
      guard !segments.isEmpty else { return 0 }
      let sum = segments.reduce(0) { $0 + $1.width }
      return sum + separatorWidth * (segments.count - 1)
    }

    func joinSegments(_ segments: [HintSegment], separator: String) -> String {
      guard !segments.isEmpty else { return "" }
      return segments.map { $0.rendered }.joined(separator: separator)
    }

    let infoText: String = {
      if let error = state.find.regexError {
        return "regex error: \(error)"
      }
      guard !state.find.field.text.isEmpty else { return "" }
      let total = state.find.matches.count
      if total == 0 { return "0/0" }
      return "\(state.find.currentIndex + 1)/\(total)"
    }()

    let infoSegment: HintSegment? = infoText.isEmpty
      ? nil
      : makeSegment(plain: infoText, rendered: Terminal.brightBlack + infoText + Terminal.reset)

    let shortcutSegments: [HintSegment] = [
      makeSegment(
        plain: "⌃G next",
        rendered: "\(Terminal.ansiCyan6)⌃G\(Terminal.reset) \(Terminal.brightBlack)next\(Terminal.reset)"),
      makeSegment(
        plain: "⌃R prev",
        rendered: "\(Terminal.ansiCyan6)⌃R\(Terminal.reset) \(Terminal.brightBlack)prev\(Terminal.reset)"),
      makeSegment(
        plain: "Esc done",
        rendered: "\(Terminal.ansiCyan6)Esc\(Terminal.reset) \(Terminal.brightBlack)done\(Terminal.reset)")
    ]

    let separator = "  "
    let separatorWidth = Terminal.displayWidth(of: separator)
    let availableWidth = max(0, termWidth - 2)
    let prefixWidth = Terminal.displayWidth(of: "Find: ")
    let baseColor = state.find.regexError == nil ? Terminal.grey : Terminal.red

    var chosenSegments: [HintSegment] = []
    var findRender: FindFieldRenderResult?

    let hintPriorities: [[HintSegment]] = stride(from: shortcutSegments.count, through: 0, by: -1)
      .map { Array(shortcutSegments.prefix($0)) }

    outer: for includeInfo in [true, false] {
      guard includeInfo ? (infoSegment != nil) : true else { continue }
      for hints in hintPriorities {
        var segments: [HintSegment] = []
        if includeInfo, let info = infoSegment { segments.append(info) }
        segments.append(contentsOf: hints)
        let hintsWidth = totalWidth(of: segments, separatorWidth: separatorWidth)
        let statusMaxWidth = max(1, min(availableWidth - hintsWidth, availableWidth))
        if statusMaxWidth <= prefixWidth {
          continue
        }
        let render = buildFindStatus(
          state: &state, maxWidth: statusMaxWidth, statusColumnBase: 2, baseColor: baseColor)
        let statusWidth = render.statusWidth
        if statusWidth + hintsWidth <= availableWidth {
          chosenSegments = segments
          findRender = render
          break outer
        }
      }
    }

    if findRender == nil {
      let render = buildFindStatus(
        state: &state, maxWidth: max(1, availableWidth - 2), statusColumnBase: 2, baseColor: baseColor)
      findRender = render
    }

    if let render = findRender {
      statusText = render.statusText
      statusDisplayWidth = render.statusWidth
      statusColor = baseColor
      pendingFindLayout = render.layout
    }

    controlHintsLength = totalWidth(of: chosenSegments, separatorWidth: separatorWidth)
    controlHints = joinSegments(chosenSegments, separator: separator)
  } else {
    let hints = makeControlHints(state: state)
    controlHints = hints.0
    controlHintsLength = hints.1
    let status = makeStatusLine(state: state)
    statusText = status.text
    statusColor = status.color
    statusDisplayWidth = Terminal.displayWidth(of: statusText)
    state.find.lastLayout = nil
  }

  let footerRowIndex = termRows - 1
  if footerRowIndex >= 0 {
    if state.find.active {
      let leftWidth = statusDisplayWidth
      let rightWidth = controlHintsLength
      let spacing = max(1, termWidth - 2 - leftWidth - rightWidth)
      if var layout = pendingFindLayout {
        layout.clickableFieldEndColumn = min(termWidth, layout.fieldEndColumn + spacing)
        pendingFindLayout = layout
        state.find.lastLayout = layout
      }
      let footerLine = " " + statusColor + statusText + Terminal.reset
        + String(repeating: " ", count: spacing) + controlHints
      frame[footerRowIndex] = footerLine
    } else {
      let totalLength = 1 + controlHintsLength + 1 + statusDisplayWidth + 1
      let padding = max(0, termWidth - totalLength)
      let footerLine =
        " " + controlHints + String(repeating: " ", count: padding + 1) + statusColor + statusText
        + Terminal.reset
      frame[footerRowIndex] = footerLine
    }
  }

  // Diff against previous frame
  for row in 0..<frame.count {
    let old = row < state.lastFrameLines.count ? state.lastFrameLines[row] : ""
    let new = frame[row]
    if old != new {
      print(Terminal.moveCursor(to: row + 1, col: 1) + new, terminator: "")
    }
  }

  state.lastFrameLines = frame

  // Cursor placement
  let cursorVisibleInView =
    maxVisibleRows > 0 && cursorVIndex >= vScroll && cursorVIndex < vScroll + maxVisibleRows
  var cursorMove: String? = nil
  var cursorCommand = Terminal.hideCursor

  if state.find.active {
    let footerRow = termRows
    if state.focusedControl == .findField {
      let caretColumn = max(1, min(termWidth, state.find.lastLayout?.caretColumn ?? termWidth))
      cursorMove = Terminal.moveCursor(to: footerRow, col: caretColumn)
      cursorCommand = state.find.cursorVisible ? Terminal.showCursor : Terminal.hideCursor
    } else if cursorVisibleInView {
      let displayRow = headerLines + 1 + (cursorVIndex - vScroll)
      let line = state.buffer[state.cursorLine]
      let safeStart = min(cursorVRow.start, line.count)
      let safeCursor = min(state.cursorColumn, line.count)
      let rowStartIndex = line.index(line.startIndex, offsetBy: safeStart)
      let cursorIndex = line.index(line.startIndex, offsetBy: safeCursor)
      let prefix = String(line[rowStartIndex..<cursorIndex])
      let cursorVisualOffset = Terminal.displayWidth(of: prefix)
      let baseColumn = gutterWidth + 1
      let displayCol = baseColumn + cursorVisualOffset
      cursorMove = Terminal.moveCursor(to: displayRow, col: displayCol)
      cursorCommand = state.cursorVisible ? Terminal.showCursor : Terminal.hideCursor
    }
  } else if cursorVisibleInView {
    let displayRow = headerLines + 1 + (cursorVIndex - vScroll)
    let line = state.buffer[state.cursorLine]
    let safeStart = min(cursorVRow.start, line.count)
    let safeCursor = min(state.cursorColumn, line.count)
    let rowStartIndex = line.index(line.startIndex, offsetBy: safeStart)
    let cursorIndex = line.index(line.startIndex, offsetBy: safeCursor)
    let prefix = String(line[rowStartIndex..<cursorIndex])
    let cursorVisualOffset = Terminal.displayWidth(of: prefix)
    let baseColumn = gutterWidth + 1
    let displayCol = baseColumn + cursorVisualOffset
    cursorMove = Terminal.moveCursor(to: displayRow, col: displayCol)
    cursorCommand = state.cursorVisible ? Terminal.showCursor : Terminal.hideCursor
  }

  if let move = cursorMove {
    print(move, terminator: "")
  }
  print(cursorCommand, terminator: "")
  fflush(stdout)
}

/// Produces the footer status text (line/column or selection summary) and its color.
private func makeStatusLine(state: EditorState) -> (text: String, color: String) {
  if state.find.active {
    let prefix = state.focusedControl == .document ? "Find ▷ " : "Find: "
    return ("\(prefix)\(state.find.field.text)", state.find.regexError == nil ? Terminal.grey : Terminal.red)
  }

  let currentLine = state.cursorLine + 1

  guard state.hasSelection, let startSel = state.selectionStart, let endSel = state.selectionEnd else {
    return ("ln \(currentLine), col \(state.cursorColumn + 1)", Terminal.grey)
  }

  let (start, end) = state.normalizeSelection(start: startSel, end: endSel)
  let lineCount = countSelectedLines(in: state, from: start, to: end)
  let characterCount = countSelectedCharacters(in: state, from: start, to: end)
  return ("lns \(lineCount), chars \(characterCount)", Terminal.grey)
}

/// Counts the number of logical lines covered by the current selection.
private func countSelectedLines(in state: EditorState, from start: (line: Int, column: Int), to end: (line: Int, column: Int)) -> Int {
  if start.line == end.line { return 1 }
  return max(1, end.line - start.line + 1)
}

/// Computes the character count of the selection, including newline separators.
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

/// Indicates whether the specified line falls within the active selection.
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

/// Builds the footer control-hint string and reports its display width.
private func makeControlHints(state: EditorState) -> (String, Int) {
  let hasDocumentSelection = state.hasSelection
  let hasFindSelection: Bool = {
    guard state.focusedControl == .findField, let selection = state.find.field.selection else { return false }
    return !selection.isEmpty
  }()

  var shortcuts: [(String, String)] = [
    ("⌃W", "close")
  ]

  if !hasDocumentSelection {
    shortcuts.append(("⌃S", "save"))
  }

  if !hasDocumentSelection {
    shortcuts.append(("⌃F", "find"))
  }

  if !state.redoStack.isEmpty {
    shortcuts.append(("⌃Y", "redo"))
  } else if !state.undoStack.isEmpty {
    shortcuts.append(("⌃Z", "undo"))
  }

  if hasDocumentSelection {
    shortcuts.append(("⌃X", "cut"))
  }

  if hasDocumentSelection || hasFindSelection {
    shortcuts.append(("⌃C", "copy"))
  }

  shortcuts.append(("⌃V", "paste"))

  let parts = shortcuts.map { hint -> (String, Int) in
    let textLength = Terminal.displayWidth(of: hint.0) + 1 + Terminal.displayWidth(of: hint.1)
    let rendered = "\(Terminal.ansiCyan6)\(hint.0)\(Terminal.reset) "
      + "\(Terminal.brightBlack)\(hint.1)\(Terminal.reset)"
    return (rendered, textLength)
  }
  let separator = "  "
  let separatorWidth = Terminal.displayWidth(of: separator)
  let renderedString = parts.enumerated().map { index, element in
    index == 0 ? element.0 : separator + element.0
  }.joined()
  let totalLength = parts.reduce(0) { $0 + $1.1 } + separatorWidth * max(0, parts.count - 1)
  return (renderedString, totalLength)
}
