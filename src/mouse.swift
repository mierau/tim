import Foundation

func handleMouseEvent(event: MouseEvent, state: inout EditorState) {
  let termSize = Terminal.getTerminalSize()
  let leftInset = state.showLineNumbers ? 5 : 1

  if event.button >= 64 && event.button <= 67 {
    if event.isPress {
      let contentWidth = max(1, termSize.cols - (leftInset + 1))
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
      let clamped = min(max(0, newOffset), maxOffset)
      if clamped != state.visualScrollOffset {
        state.visualScrollOffset = clamped
        state.pinCursorToView = false
        state.needsRedraw = true
      }
    }
    return
  }

  let isMotion = (event.button & 32) != 0
  let baseButton = event.button & 0b11

  if baseButton == 0 && !isMotion {
    if state.find.active,
      let layout = state.find.lastLayout,
      event.y == termSize.rows
    {
      if !event.isPress {
        state.isFindFieldDragging = false
        state.isFindFieldWordSelection = false
        return
      }

      let now = Date()

      if event.x < layout.fieldStartColumn {
        state.setFocus(.findField)
        let anchor = layout.columns.first?.index ?? 0
        state.find.field.clearSelection()
        state.setFindCursor(anchor)
        state.find.field.beginSelection(at: anchor)
        state.isFindFieldDragging = true
        state.isFindFieldWordSelection = false
        state.find.cursorVisible = true
        state.find.lastBlinkTime = now
        state.find.lastClickTime = now
        state.find.lastClickIndex = anchor
        state.find.lastClickCount = 1
        state.needsRedraw = true
        return
      }

      if event.x >= layout.fieldStartColumn && event.x < layout.clickableFieldEndColumn {
        let targetIndex: Int
        if let column = layout.columns.first(where: { $0.columnRange.contains(event.x) }) {
          targetIndex = column.index
        } else {
          targetIndex = layout.columns.last?.index ?? state.find.field.cursor
        }

        state.setFocus(.findField)

        if event.hasShift && state.focusedControl == .findField {
          state.setFindCursor(targetIndex, expandSelection: true)
          state.isFindFieldDragging = false
          state.isFindFieldWordSelection = false
          state.find.cursorVisible = true
          state.find.lastBlinkTime = now
          state.find.lastClickTime = now
          state.find.lastClickIndex = targetIndex
          state.find.lastClickCount = 1
          state.needsRedraw = true
          return
        }

        var clickCount = 1
        if let lastTime = state.find.lastClickTime,
          now.timeIntervalSince(lastTime) <= doubleClickThreshold,
          let lastIndex = state.find.lastClickIndex,
          abs(lastIndex - targetIndex) <= 1
        {
          clickCount = state.find.lastClickCount + 1
        }

        if clickCount >= 3 {
          state.find.field.selectAll()
          state.isFindFieldDragging = false
          state.isFindFieldWordSelection = false
        } else if clickCount == 2 && !state.find.field.text.isEmpty {
          let maxIndex = max(0, state.find.field.text.count - 1)
          let selectIndex = max(0, min(maxIndex, targetIndex >= state.find.field.text.count ? targetIndex - 1 : targetIndex))
          state.find.field.selectWord(at: selectIndex)
          state.isFindFieldDragging = true
          state.isFindFieldWordSelection = true
        } else {
          state.find.field.clearSelection()
          state.setFindCursor(targetIndex)
          state.find.field.beginSelection(at: targetIndex)
          state.isFindFieldDragging = true
          state.isFindFieldWordSelection = false
        }

        state.find.cursorVisible = true
        state.find.lastBlinkTime = now
        state.find.lastClickTime = now
        state.find.lastClickIndex = targetIndex
        state.find.lastClickCount = clickCount
        state.needsRedraw = true
        return
      }

      state.isFindFieldDragging = false
      state.isFindFieldWordSelection = false
      return
    }
    let contentTop = 2
    let localRow = event.y - contentTop
    let editorCol = max(0, event.x - (leftInset + 1))
    if localRow >= 0 {
      let contentWidth = max(1, termSize.cols - (leftInset + 1))
      let headerLines = 1
      let footerLines = 2
      let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
      let scrollbarColStart = leftInset + 1 + contentWidth
      if event.x >= scrollbarColStart {
        let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
        let totalRows = max(snapshot.rows.count, 1)
        let trackHeight = maxVisibleRows
        let (handleStart, handleHeight, maxOffset) = Scrollbar.compute(
          totalRows: totalRows, trackHeight: trackHeight, offset: state.visualScrollOffset)
        switch Scrollbar.hitTest(localRow: localRow, start: handleStart, height: handleHeight) {
        case .above:
          let step = Scrollbar.pageStep(trackHeight: trackHeight, fraction: 0.9)
          let updated = max(0, state.visualScrollOffset - step)
          if updated != state.visualScrollOffset {
            state.visualScrollOffset = updated
            state.pinCursorToView = false
            state.needsRedraw = true
          }
          return
        case .below:
          let step = Scrollbar.pageStep(trackHeight: trackHeight, fraction: 0.9)
          let desired = min(maxOffset, state.visualScrollOffset + step)
          let updated = max(0, min(desired, maxOffset))
          if updated != state.visualScrollOffset {
            state.visualScrollOffset = updated
            state.pinCursorToView = false
            state.needsRedraw = true
          }
          return
        case .handle:
          let pos = min(max(localRow - handleHeight / 2, 0), max(0, trackHeight - handleHeight))
          let newOffset = Int(
            round(Double(pos) / Double(max(1, trackHeight - handleHeight)) * Double(maxOffset)))
          let desired = min(maxOffset, max(0, newOffset))
          if desired != state.visualScrollOffset {
            state.visualScrollOffset = desired
            state.pinCursorToView = false
            state.needsRedraw = true
          }
          state.isScrollbarDragging = true
          state.isDragging = false
          state.selectionMode = .none
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
      state.dragSelectionPreferredColumn = targetColumn
      state.isScrollbarDragging = false
      if event.isPress {
      if state.find.active {
        state.setFocus(.document)
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
          state.dragSelectionPreferredColumn = state.cursorColumn
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
        state.dragSelectionPreferredColumn = state.cursorColumn
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
          state.dragSelectionPreferredColumn = state.cursorColumn
          state.clampCursor()
          state.isDragging = true
          state.selectionMode = .word(
            anchorLine: targetLine, anchorStart: range.start, anchorEnd: range.end)
        }
      } else {
        state.cursorLine = targetLine
        state.cursorColumn = targetColumn
        state.dragSelectionPreferredColumn = state.cursorColumn
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
      state.needsRedraw = true
    } else {
      if state.isDragging {
        state.isDragging = false
        state.dragAutoscrollDirection = 0
        state.dragSelectionPreferredColumn = state.cursorColumn
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
    if state.find.active, state.isFindFieldDragging, let layout = state.find.lastLayout {
      var clampedX = event.x
      if clampedX < layout.fieldStartColumn { clampedX = layout.fieldStartColumn }
      if clampedX >= layout.clickableFieldEndColumn { clampedX = layout.clickableFieldEndColumn - 1 }
      let targetIndex: Int
      if let column = layout.columns.first(where: { $0.columnRange.contains(clampedX) }) {
        targetIndex = column.index
      } else {
        targetIndex = layout.columns.last?.index ?? state.find.field.cursor
      }
      if state.isFindFieldWordSelection {
        if !state.find.field.text.isEmpty {
          let anchorIndex = state.find.field.selectionAnchor ?? 0
          let anchorProbe = anchorIndex >= state.find.field.text.count ? max(0, state.find.field.text.count - 1) : anchorIndex
          let anchorRange = state.find.field.wordRange(at: anchorProbe)
          let targetProbe = targetIndex >= state.find.field.text.count ? max(0, state.find.field.text.count - 1) : targetIndex
          let targetRange = state.find.field.wordRange(at: targetProbe)
          var newLower = anchorRange.lowerBound
          var newUpper = anchorRange.upperBound
          var cursorPos = targetIndex
          if targetRange.upperBound >= anchorRange.upperBound {
            newUpper = targetRange.upperBound
            cursorPos = targetRange.upperBound
          }
          if targetRange.lowerBound <= anchorRange.lowerBound {
            newLower = targetRange.lowerBound
            cursorPos = targetRange.lowerBound
          }
          state.find.field.selection = newLower..<newUpper
          state.find.field.selectionAnchor = anchorRange.lowerBound
          state.find.field.cursor = cursorPos
          state.find.field.ensureCursorVisible()
        }
      } else {
        state.find.field.setCursor(targetIndex, expandSelection: true)
        state.find.field.ensureCursorVisible()
      }
      state.find.cursorVisible = true
      state.find.lastBlinkTime = Date()
      state.needsRedraw = true
      return
    }
    if state.isDragging || state.isScrollbarDragging {
      let contentTop = 2
      var localRow = event.y - contentTop
      let editorCol = max(0, event.x - (leftInset + 1))
      let termSize = Terminal.getTerminalSize()
      let contentWidth = max(1, termSize.cols - (leftInset + 1))
      let headerLines = 1
      let footerLines = 2
      let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
      let snapshot = state.layoutCache.snapshot(for: state, contentWidth: contentWidth)
      let vrows = snapshot.rows
      guard !vrows.isEmpty else { return }

      if state.isScrollbarDragging && localRow >= 0 {
        let totalRows = max(vrows.count, 1)
        let trackHeight = maxVisibleRows
        let maxOffset = max(0, totalRows - trackHeight)
        var handleHeight = min(trackHeight, totalRows)
        if totalRows > trackHeight {
          handleHeight = max(1, Int(Double(trackHeight * trackHeight) / Double(totalRows)))
        }
        let pos = min(max(localRow - handleHeight / 2, 0), max(0, trackHeight - handleHeight))
        let denom = max(1, trackHeight - handleHeight)
        let newOffset = Int(round(Double(pos) / Double(denom) * Double(maxOffset)))
        let desired = min(maxOffset, max(0, newOffset))
        state.visualScrollOffset = desired
        state.needsRedraw = true
        return
      }

      let totalRows = max(vrows.count, 1)
      let maxOffset = max(0, totalRows - maxVisibleRows)
      var scrolled = false

      if localRow < 0 {
        if state.visualScrollOffset > 0 {
          state.visualScrollOffset -= 1
          scrolled = true
        }
        localRow = 0
        state.dragAutoscrollDirection = -1
      } else if localRow >= maxVisibleRows {
        if state.visualScrollOffset < maxOffset {
          state.visualScrollOffset += 1
          scrolled = true
        }
        localRow = maxVisibleRows - 1
        state.dragAutoscrollDirection = 1
      } else {
        state.dragAutoscrollDirection = 0
      }

      localRow = max(0, min(localRow, maxVisibleRows - 1))
      let vIndex = max(0, min(state.visualScrollOffset + localRow, vrows.count - 1))
      let vr = vrows[vIndex]
      let targetLine = vr.lineIndex
      let line = state.buffer[targetLine]
      let targetColumn = min(vr.start + editorCol, line.count)

      if scrolled {
        state.needsRedraw = true
        state.pinCursorToView = true
      } else if state.dragAutoscrollDirection != 0 {
        state.dragAutoscrollDirection = 0
      }

      state.updateSelectionDuringDrag(targetLine: targetLine, targetColumn: targetColumn)
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
