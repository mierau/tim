import Foundation

func handleEscapeSequence(state: inout EditorState) {
  let next1 = readKey()
  if next1 == -1 { return }

  if next1 == 127 || next1 == 8 {
    smartDeleteBackward(state: &state)
    return
  }

  if handleOptionWord(byte: next1, shift: isUppercaseLetter(next1), state: &state) {
    return
  }

  if next1 == 27 {
    let next2 = readKey()
    if next2 == -1 { return }
    if next2 == 91 {
      handleCSI(meta: true, state: &state)
      return
    }
    if next2 == 27 {
      let next3 = readKey()
      if next3 == -1 { return }
      if next3 == 91 {
        handleCSI(meta: true, state: &state)
        return
      }
      if handleOptionWord(byte: next3, shift: isUppercaseLetter(next3), state: &state) {
        return
      }
    } else {
      if handleOptionWord(byte: next2, shift: isUppercaseLetter(next2), state: &state) {
        return
      }
    }
    return
  }

  if next1 == 91 {
    handleCSI(meta: false, state: &state)
    return
  }
}

private func handleCSI(meta: Bool, state: inout EditorState) {
  let value = readKey()
  if value == -1 { return }

  switch value {
  case 60:
    if let event = parseMouseEvent() { handleMouseEvent(event: event, state: &state) }
    return
  case 49:
    let next = readKey()
    if next == 59, let (modifier, arrow) = readModifierAndArrow() {
      if routeModifiedArrow(modifier: modifier, arrow: arrow, forcedAlt: meta, state: &state) {
        return
      }
    } else if next == 126 {
      moveToBeginningOfLine(state: &state)
    }
    return
  case 51:
    if readKey() == 126 { forwardDelete(state: &state) }
    return
  case 53:
    if readKey() == 126 { pageScroll(up: true, state: &state, fraction: 0.9) }
    return
  case 54:
    if readKey() == 126 { pageScroll(up: false, state: &state, fraction: 0.9) }
    return
  case 52:
    if readKey() == 126 { moveToEndOfLine(state: &state) }
    return
  case 65, 66, 67, 68:
    let arrow = value

    if readOptionalModifier(after: arrow, forcedAlt: meta, state: &state) {
      return
    }

    if meta {
      if arrow == 67 || arrow == 68 {
        handleShiftOptionArrow(arrow, state: &state)
      } else {
        handleOptionArrow(arrow, state: &state)
      }
      return
    }

    switch arrow {
    case 65:
      if collapseSelectionVertically(direction: -1, state: &state) {
        // handled
      } else if moveCursorByVisualRow(direction: -1, state: &state) {
        // handled
      } else if state.cursorLine > 0 {
        state.cursorLine -= 1
        state.clampCursor()
      } else {
        state.cursorColumn = 0
        state.clampCursor()
      }
      state.showCursor()
    case 66:
      if collapseSelectionVertically(direction: 1, state: &state) {
        // handled
      } else if moveCursorByVisualRow(direction: 1, state: &state) {
        // handled
      } else if state.cursorLine < state.buffer.count - 1 {
        state.cursorLine += 1
        state.clampCursor()
      } else {
        state.cursorColumn = state.buffer[state.cursorLine].count
        state.clampCursor()
      }
      state.showCursor()
    case 67:
      if state.hasSelection {
        let (_, end) = state.normalizeSelection(
          start: state.selectionStart!, end: state.selectionEnd!)
        state.cursorLine = end.line
        state.cursorColumn = end.column
        state.clearSelection()
      } else {
        let lineLength = state.buffer[state.cursorLine].count
        if state.cursorColumn < lineLength {
          state.cursorColumn += 1
        } else if state.cursorLine < state.buffer.count - 1 {
          state.cursorLine += 1
          state.cursorColumn = 0
        }
      }
      state.showCursor()
    case 68:
      if state.hasSelection {
        let (start, _) = state.normalizeSelection(
          start: state.selectionStart!, end: state.selectionEnd!)
        state.cursorLine = start.line
        state.cursorColumn = start.column
        state.clearSelection()
      } else {
        if state.cursorColumn > 0 {
          state.cursorColumn -= 1
        } else if state.cursorLine > 0 {
          state.cursorLine -= 1
          state.cursorColumn = state.buffer[state.cursorLine].count
        }
      }
      state.showCursor()
    default:
      break
    }
  default:
    return
  }
}

func handleShiftArrow(_ arrow: Int, state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  switch arrow {
  case 65:
    if state.cursorLine > 0 {
      state.cursorLine -= 1
      let targetLineLength = state.buffer[state.cursorLine].count
      state.cursorColumn = min(state.cursorColumn, targetLineLength)
    }
    state.updateSelection()
    state.showCursor()
  case 66:
    if state.cursorLine < state.buffer.count - 1 {
      state.cursorLine += 1
      let targetLineLength = state.buffer[state.cursorLine].count
      state.cursorColumn = min(state.cursorColumn, targetLineLength)
    }
    state.updateSelection()
    state.showCursor()
  case 67:
    let lineLength = state.buffer[state.cursorLine].count
    if state.cursorColumn < lineLength {
      state.cursorColumn += 1
    } else if state.cursorLine < state.buffer.count - 1 {
      state.cursorLine += 1
      state.cursorColumn = 0
    }
    state.updateSelection()
    state.showCursor()
  case 68:
    if state.cursorColumn > 0 {
      state.cursorColumn -= 1
    } else if state.cursorLine > 0 {
      state.cursorLine -= 1
      state.cursorColumn = state.buffer[state.cursorLine].count
    }
    state.updateSelection()
    state.showCursor()
  default: break
  }
}

func handleShiftCtrlArrow(_ arrow: Int, state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  switch arrow {
  case 67: extendSelectionWordForward(state: &state)
  case 68: extendSelectionWordBackward(state: &state)
  default: break
  }
  state.updateSelection()
}

private func handleOptionArrow(_ arrow: Int, state: inout EditorState) {
  state.clearSelection()
  switch arrow {
  case 65:  // Up
    if state.cursorColumn == 0 {
      if state.cursorLine > 0 {
        state.cursorLine -= 1
        state.cursorColumn = 0
        state.clampCursor()
      }
    } else {
      moveToBeginningOfLine(state: &state)
    }
  case 66:  // Down
    let lineEnd = state.buffer[state.cursorLine].count
    if state.cursorColumn >= lineEnd {
      if state.cursorLine < state.buffer.count - 1 {
        state.cursorLine += 1
        state.cursorColumn = state.buffer[state.cursorLine].count
        state.clampCursor()
      }
    } else {
      moveToEndOfLine(state: &state)
    }
  case 67:  // Right
    jumpWordForward(state: &state)
  case 68:  // Left
    jumpWordBackward(state: &state)
  default:
    return
  }
  state.pinCursorToView = true
  state.showCursor()
}

private func handleShiftOptionArrow(_ arrow: Int, state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  switch arrow {
  case 65:
    if !moveCursorByVisualRow(direction: -1, state: &state) {
      if state.cursorLine > 0 {
        state.cursorLine -= 1
        state.cursorColumn = min(state.cursorColumn, state.buffer[state.cursorLine].count)
      }
    }
    state.updateSelection()
  case 66:
    if !moveCursorByVisualRow(direction: 1, state: &state) {
      if state.cursorLine < state.buffer.count - 1 {
        state.cursorLine += 1
        state.cursorColumn = min(state.cursorColumn, state.buffer[state.cursorLine].count)
      }
    }
    state.updateSelection()
  case 67:
    extendSelectionWordForward(state: &state)
    state.updateSelection()
  case 68:
    extendSelectionWordBackward(state: &state)
    state.updateSelection()
  default:
    return
  }
  state.showCursor()
}

private func handleOptionWord(byte: Int, shift: Bool, state: inout EditorState) -> Bool {
  guard byte >= 0 && byte <= 255 else { return false }
  let lower = byte | 0x20
  switch lower {
  case 102:  // 'f'
    if shift {
      if !state.hasSelection { state.startSelection() }
      extendSelectionWordForward(state: &state)
      state.updateSelection()
    } else {
      jumpWordForward(state: &state)
    }
  case 98:  // 'b'
    if shift {
      if !state.hasSelection { state.startSelection() }
      extendSelectionWordBackward(state: &state)
      state.updateSelection()
    } else {
      jumpWordBackward(state: &state)
    }
  default:
    return false
  }
  state.pinCursorToView = true
  state.showCursor()
  return true
}

private func isUppercaseLetter(_ byte: Int) -> Bool {
  return byte >= 65 && byte <= 90
}

private func readOptionalModifier(after arrow: Int, forcedAlt: Bool = false, state: inout EditorState) -> Bool {
  let flags = fcntl(STDIN_FILENO, F_GETFL)
  let _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
  var buffer = UInt8(0)
  let result = read(STDIN_FILENO, &buffer, 1)
  let _ = fcntl(STDIN_FILENO, F_SETFL, flags)
  if result > 0 {
    if buffer == UInt8(59) {  // ';'
      if let (modifier, parsedArrow) = readModifierAndArrow() {
        return routeModifiedArrow(modifier: modifier, arrow: parsedArrow, forcedAlt: forcedAlt, state: &state)
      }
    }
  }
  return false
}

private func readModifierAndArrow() -> (modifier: Int, arrow: Int)? {
  var digits: [Int] = []
  while true {
    let value = readKey()
    if value == -1 { return nil }
    if value >= 48 && value <= 57 {
      digits.append(value - 48)
      continue
    }
    let modifier = digits.reduce(0) { $0 * 10 + $1 }
    return (modifier, value)
  }
}

@discardableResult
private func routeModifiedArrow(modifier: Int, arrow: Int, forcedAlt: Bool = false, state: inout EditorState) -> Bool {
  if modifier <= 1 && !forcedAlt { return false }
  let rawBits = max(0, modifier - 1)
  let hasShift = (rawBits & 1) != 0
  let hasAlt = forcedAlt || (rawBits & 2) != 0
  let hasCtrl = (rawBits & 4) != 0

  if hasAlt && hasShift && !hasCtrl {
    handleShiftOptionArrow(arrow, state: &state)
    return true
  }

  if hasAlt && !hasCtrl {
    handleOptionArrow(arrow, state: &state)
    return true
  }

  if hasShift && hasCtrl && !hasAlt {
    handleShiftCtrlArrow(arrow, state: &state)
    return true
  }

  if hasShift && !hasAlt && !hasCtrl {
    handleShiftArrow(arrow, state: &state)
    return true
  }

  return false
}

func extendSelectionWordForward(state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  moveCursorForwardByWord(state: &state)
  state.updateSelection()
}

func extendSelectionWordBackward(state: inout EditorState) {
  if !state.hasSelection { state.startSelection() }
  moveCursorBackwardByWord(state: &state)
  state.updateSelection()
}

func pageScroll(up: Bool, state: inout EditorState, fraction: Double = 1.0) {
  let termSize = Terminal.getTerminalSize()
  let contentWidth = max(1, termSize.cols - 6)
  let headerLines = 1
  let footerLines = 2
  let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
  var vrows = state.layoutCache.snapshot(for: state, contentWidth: contentWidth).rows
  let (curVIndex, curVRow) = findCursorVisualIndex(state: state, rows: vrows)
  let colInRow = max(0, state.cursorColumn - curVRow.start)
  let page = maxVisibleRows
  let frac = max(0.0, min(1.0, fraction))
  let delta = max(1, Int(floor(Double(page) * frac)))
  var newOffset = state.visualScrollOffset
  var newCursorV = curVIndex
  let totalRows = max(vrows.count, 1)
  if up {
    newOffset = max(0, newOffset - delta)
    newCursorV = max(0, curVIndex - delta)
  } else {
    let maxOffset = max(0, totalRows - maxVisibleRows)
    newOffset = min(maxOffset, newOffset + delta)
    newCursorV = min(totalRows - 1, curVIndex + delta)
  }
  vrows = state.layoutCache.snapshot(for: state, contentWidth: contentWidth).rows
  let newRow = vrows[newCursorV]
  let newColInRow = min(colInRow, max(0, newRow.end - newRow.start))
  state.cursorLine = newRow.lineIndex
  state.cursorColumn = newRow.start + newColInRow
  state.clampCursor()
  let maxOffsetActual = max(0, vrows.count - maxVisibleRows)
  state.visualScrollOffset = min(newOffset, maxOffsetActual)
  state.pinCursorToView = true
  state.needsRedraw = true
}

@discardableResult
func collapseSelectionVertically(direction: Int, state: inout EditorState) -> Bool {
  guard state.hasSelection else { return false }
  let (start, end) = state.normalizeSelection(
    start: state.selectionStart!, end: state.selectionEnd!)

  let movingUp = direction < 0
  let anchor = movingUp ? start : end

  let originalLine = state.cursorLine
  let originalColumn = state.cursorColumn

  state.cursorLine = anchor.line
  state.cursorColumn = anchor.column
  state.clampCursor()

  if moveCursorByVisualRow(direction: direction, state: &state) {
    state.clearSelection()
    state.pinCursorToView = true
    return true
  }

  state.cursorLine = originalLine
  state.cursorColumn = originalColumn

  var targetLine = anchor.line
  if movingUp {
    if anchor.line > 0 { targetLine = anchor.line - 1 }
  } else {
    if anchor.line < state.buffer.count - 1 { targetLine = anchor.line + 1 }
  }

  let preferredColumn = movingUp ? start.column : end.column
  let lineLen = state.buffer[targetLine].count
  state.cursorLine = targetLine
  state.cursorColumn = min(preferredColumn, lineLen)
  state.clampCursor()
  state.pinCursorToView = true
  state.clearSelection()
  return true
}

@discardableResult
func moveCursorByVisualRow(direction: Int, state: inout EditorState) -> Bool {
  if direction == 0 { return false }
  state.clampCursor()
  let termSize = Terminal.getTerminalSize()
  let contentWidth = max(1, termSize.cols - 6)
  var visualRows = state.layoutCache.snapshot(for: state, contentWidth: contentWidth).rows
  if visualRows.isEmpty { return false }

  let (currentIndex, currentRow) = findCursorVisualIndex(state: state, rows: visualRows)
  let targetIndex = currentIndex + direction
  if targetIndex < 0 { return false }
  if targetIndex >= visualRows.count {
    visualRows = state.layoutCache.snapshot(for: state, contentWidth: contentWidth).rows
    if targetIndex >= visualRows.count { return false }
  }

  let nextRow = visualRows[targetIndex]
  let colInRow = max(0, state.cursorColumn - currentRow.start)
  let rowSpan = max(0, nextRow.end - nextRow.start)
  let newOffset = min(colInRow, rowSpan)
  state.cursorLine = nextRow.lineIndex
  state.cursorColumn = nextRow.start + newOffset
  state.clampCursor()
  state.pinCursorToView = true
  return true
}
