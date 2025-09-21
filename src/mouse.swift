import Foundation

func handleMouseEvent(event: MouseEvent, state: inout EditorState) {
  if event.button >= 64 && event.button <= 67 {
    if event.isPress {
      let termSize = Terminal.getTerminalSize()
      let contentWidth = max(1, termSize.cols - 6)
      let headerLines = 1
      let footerLines = 2
      let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
      let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
      let totalRows = max(snapshot.rows.count, 1)
      let delta = 1
      var newOffset = state.visualScrollOffset
      if event.button == 64 {
        newOffset = max(0, newOffset - delta)
      } else if event.button == 65 {
        let maxOffset = max(0, totalRows - maxVisibleRows)
        newOffset = min(maxOffset, newOffset + delta)
      }
      let maxOffset = max(0, totalRows - maxVisibleRows)
      state.visualScrollOffset = min(max(0, newOffset), maxOffset)
      state.pinCursorToView = false
      state.needsRedraw = true
    }
    return
  }

  let isMotion = (event.button & 32) != 0
  let baseButton = event.button & 0b11

  if baseButton == 0 && !isMotion {
    let contentTop = 2
    let localRow = event.y - contentTop
    let editorCol = max(0, event.x - 6)
    if localRow >= 0 {
      let termSize = Terminal.getTerminalSize()
      let contentWidth = max(1, termSize.cols - 6)
      let headerLines = 1
      let footerLines = 2
      let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
      let scrollbarColStart = 6 + contentWidth
      if event.x >= scrollbarColStart {
        let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
        let totalRows = max(snapshot.rows.count, 1)
        let trackHeight = maxVisibleRows
        let (handleStart, handleHeight, maxOffset) = Scrollbar.compute(
          totalRows: totalRows, trackHeight: trackHeight, offset: state.visualScrollOffset)
        switch Scrollbar.hitTest(localRow: localRow, start: handleStart, height: handleHeight) {
        case .above:
          let step = Scrollbar.pageStep(trackHeight: trackHeight, fraction: 0.9)
          state.visualScrollOffset = max(0, state.visualScrollOffset - step)
          state.pinCursorToView = false
          state.needsRedraw = true
          return
        case .below:
          let step = Scrollbar.pageStep(trackHeight: trackHeight, fraction: 0.9)
          let desired = min(maxOffset, state.visualScrollOffset + step)
          state.visualScrollOffset = max(0, min(desired, maxOffset))
          state.pinCursorToView = false
          state.needsRedraw = true
          return
        case .handle:
          let pos = min(max(localRow - handleHeight / 2, 0), max(0, trackHeight - handleHeight))
          let newOffset = Int(
            round(Double(pos) / Double(max(1, trackHeight - handleHeight)) * Double(maxOffset)))
          let desired = min(maxOffset, max(0, newOffset))
          state.visualScrollOffset = desired
          state.isScrollbarDragging = true
          state.isDragging = false
          state.selectionMode = .none
          state.pinCursorToView = false
          state.needsRedraw = true
          return
        }
      }
      // Text area click
      let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
      let vrows = snapshot.rows
      guard !vrows.isEmpty else { return }
      let vIndex = min(state.visualScrollOffset + localRow, max(0, vrows.count - 1))
      let vr = vrows[vIndex]
      let targetLine = vr.lineIndex
      let line = state.buffer[targetLine]
      let targetColumn = min(vr.start + editorCol, line.count)
      state.isScrollbarDragging = false
      if event.isPress {
        if state.find.active {
          state.setFindFocus(.document)
        }
        state.pinCursorToView = false
        let now = Date()
        if event.hasShift {
          var anchorPoint: (line: Int, column: Int)
          if state.hasSelection, let startSel = state.selectionStart, let endSel = state.selectionEnd {
            let (start, end) = state.normalizeSelection(start: startSel, end: endSel)
            if state.cursorLine == start.line && state.cursorColumn == start.column {
              anchorPoint = end
            } else {
              anchorPoint = start
            }
          } else {
            anchorPoint = (line: state.cursorLine, column: state.cursorColumn)
          }

          state.selectionMode = .character(anchorLine: anchorPoint.line, anchorColumn: anchorPoint.column)
          let (selStart, selEnd) = state.normalizeSelection(
            start: anchorPoint, end: (line: targetLine, column: targetColumn))
          state.selectionStart = selStart
          state.selectionEnd = selEnd
          state.cursorLine = targetLine
          state.cursorColumn = targetColumn
          state.clampCursor()
          state.showCursor()
          state.isDragging = false
          state.isScrollbarDragging = false
          state.lastClickTime = now
          state.lastClickLine = targetLine
          state.lastClickColumn = targetColumn
          state.lastClickCount = 1
          state.pinCursorToView = true
          state.needsRedraw = true
          return
        }

        var clickCount = 1
        if let lastTime = state.lastClickTime,
          let lastLine = state.lastClickLine,
          let lastCol = state.lastClickColumn,
          now.timeIntervalSince(lastTime) <= doubleClickThreshold,
          lastLine == targetLine,
          abs(lastCol - targetColumn) <= 1
        {
          clickCount = state.lastClickCount + 1
        }
        if clickCount >= 3 {
          let lineLen = line.count
          state.selectionStart = (targetLine, 0)
          state.selectionEnd = (targetLine, lineLen)
          state.cursorLine = targetLine
          state.cursorColumn = lineLen
          state.clampCursor()
          state.isDragging = true
          state.selectionMode = .line(anchorLine: targetLine)
        } else if clickCount == 2 {
          if !line.isEmpty {
            let idx = max(0, min(targetColumn, max(0, line.count - 1)))
            let range = wordRange(in: line, at: idx)
            state.selectionStart = (targetLine, range.start)
            state.selectionEnd = (targetLine, range.end)
            state.cursorLine = targetLine
            state.cursorColumn = range.end
            state.clampCursor()
            state.isDragging = true
            state.selectionMode = .word(
              anchorLine: targetLine, anchorStart: range.start, anchorEnd: range.end)
          }
        } else {
          state.cursorLine = targetLine
          state.cursorColumn = targetColumn
          state.clampCursor()
          state.isDragging = true
          state.selectionMode = .character(
            anchorLine: state.cursorLine, anchorColumn: state.cursorColumn)
          state.selectionStart = (state.cursorLine, state.cursorColumn)
          state.selectionEnd = (state.cursorLine, state.cursorColumn)
        }
        state.lastClickTime = now
        state.lastClickLine = targetLine
        state.lastClickColumn = targetColumn
        state.lastClickCount = clickCount
        state.pinCursorToView = true
      } else {
        if state.isDragging {
          state.isDragging = false
          if case .character? = selectionModeForClearing(state), let start = state.selectionStart,
            start.line == targetLine && start.column == targetColumn
          {
            state.clearSelection()
          }
        }
        if state.isScrollbarDragging { state.isScrollbarDragging = false }
      }
    }
  } else if baseButton == 0 && isMotion {
    if state.isDragging || state.isScrollbarDragging {
      let contentTop = 2
      let localRow = event.y - contentTop
      let editorCol = max(0, event.x - 6)
      if localRow >= 0 {
        if state.isScrollbarDragging {
          let termSize = Terminal.getTerminalSize()
          let contentWidth = max(1, termSize.cols - 6)
          let headerLines = 1
          let footerLines = 2
          let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
          let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
          let totalRows = max(snapshot.rows.count, 1)
          let trackHeight = maxVisibleRows
          let maxOffset = max(0, totalRows - trackHeight)
          var handleHeight = min(trackHeight, totalRows)
          if totalRows > trackHeight {
            handleHeight = max(
              1, Int(Double(trackHeight) * Double(trackHeight) / Double(totalRows)))
          }
          let pos = min(max(localRow - handleHeight / 2, 0), max(0, trackHeight - handleHeight))
          let denom = max(1, trackHeight - handleHeight)
          let newOffset = Int(round(Double(pos) / Double(denom) * Double(maxOffset)))
          let desired = min(maxOffset, max(0, newOffset))
          state.visualScrollOffset = desired
          state.needsRedraw = true
          return
        }
        let termSize = Terminal.getTerminalSize()
        let contentWidth = max(1, termSize.cols - 6)
        let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
        let vrows = snapshot.rows
        guard !vrows.isEmpty else { return }
        let vIndex = min(state.visualScrollOffset + localRow, max(0, vrows.count - 1))
        let vr = vrows[vIndex]
        let targetLine = vr.lineIndex
        let line = state.buffer[targetLine]
        let targetColumn = min(vr.start + editorCol, line.count)
        switch state.selectionMode {
        case .line(let anchorLine):
          let startLine = min(anchorLine, targetLine)
          let endLine = max(anchorLine, targetLine)
          let endLen = state.buffer[endLine].count
          state.selectionStart = (startLine, 0)
          state.selectionEnd = (endLine, endLen)
          if targetLine >= anchorLine {
            state.cursorLine = endLine
            state.cursorColumn = endLen
          } else {
            state.cursorLine = startLine
            state.cursorColumn = 0
          }
          state.clampCursor()
        case .word(let anchorLine, let anchorStart, let anchorEnd):
          let range: (start: Int, end: Int)
          if line.isEmpty {
            range = (0, 0)
          } else {
            let idx = max(0, min(targetColumn, max(0, line.count - 1)))
            range = wordRange(in: line, at: idx)
          }
          func cmp(_ a: (line: Int, col: Int), _ b: (line: Int, col: Int)) -> Int {
            if a.line < b.line { return -1 }
            if a.line > b.line { return 1 }
            if a.col < b.col { return -1 }
            if a.col > b.col { return 1 }
            return 0
          }
          let targetPos = (line: targetLine, col: targetColumn)
          let aStart = (line: anchorLine, col: anchorStart)
          let aEnd = (line: anchorLine, col: anchorEnd)
          if cmp(targetPos, aEnd) >= 0 {
            state.selectionStart = (line: aStart.line, column: aStart.col)
            state.selectionEnd = (targetLine, range.end)
            state.cursorLine = targetLine
            state.cursorColumn = range.end
          } else if cmp(targetPos, aStart) <= 0 {
            state.selectionStart = (targetLine, range.start)
            state.selectionEnd = (line: aEnd.line, column: aEnd.col)
            state.cursorLine = targetLine
            state.cursorColumn = range.start
          } else {
            state.selectionStart = (line: aStart.line, column: aStart.col)
            state.selectionEnd = (line: aEnd.line, column: aEnd.col)
            state.cursorLine = anchorLine
            state.cursorColumn = anchorEnd
          }
          state.clampCursor()
        case .character:
          state.selectionEnd = (targetLine, targetColumn)
          state.cursorLine = targetLine
          state.cursorColumn = targetColumn
          state.clampCursor()
        case .none:
          break
        }
      }
    }
  }
}

private func selectionModeForClearing(_ state: EditorState) -> SelectionMode? {
  switch state.selectionMode {
  case .character:
    return state.selectionMode
  default:
    return nil
  }
}
