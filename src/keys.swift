import Foundation

func handleEscapeSequence(state: inout EditorState) {
  let next1 = readKey()
  if next1 == -1 { return }

  if next1 == 127 || next1 == 8 {
    smartDeleteBackward(state: &state)
    return
  }

  if next1 == 98 {
    jumpWordBackward(state: &state)
    return
  }  // ESC b
  if next1 == 102 {
    jumpWordForward(state: &state)
    return
  }  // ESC f
  if next1 == 27 {
    let next2 = readKey()
    if next2 == 91 {
      let next3 = readKey()
      if next3 == 67 {
        handleShiftCtrlArrow(67, state: &state)
        return
      }
      if next3 == 68 {
        handleShiftCtrlArrow(68, state: &state)
        return
      }
    }
  }

  if next1 == 91 {
    let next2 = readKey()
    if next2 == -1 { return }
    if next2 == 60 {
      if let me = parseMouseEvent() { handleMouseEvent(event: me, state: &state) }
      return
    }
    if next2 == 49 {
      let semicolon = readKey()
      if semicolon == 59 {
        let modifier = readKey()
        let arrow = readKey()
        if modifier == 50 {
          handleShiftArrow(arrow, state: &state)
          return
        } else if modifier == 51 {
          if arrow == 67 {
            jumpWordForward(state: &state)
          } else if arrow == 68 {
            jumpWordBackward(state: &state)
          }
          return
        } else if modifier == 56 {
          handleShiftCtrlArrow(arrow, state: &state)
          return
        }
      }
    }

    if next2 == 65 || next2 == 66 || next2 == 67 || next2 == 68 {
      let flags = fcntl(STDIN_FILENO, F_GETFL)
      let _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
      var char: Int8 = 0
      let result = read(STDIN_FILENO, &char, 1)
      let _ = fcntl(STDIN_FILENO, F_SETFL, flags)
      if result > 0, Int(char) == 59 {
        let modifier = readKey()
        if modifier == 50 {
          handleShiftArrow(next2, state: &state)
          return
        }
      }
    }

    if next2 == 51 {
      let tilde = readKey()
      if tilde == 126 {
        forwardDelete(state: &state)
        return
      }
    }
    if next2 == 53 {
      let tilde = readKey()
      if tilde == 126 {
        pageScroll(up: true, state: &state, fraction: 0.9)
        return
      }
    }
    if next2 == 54 {
      let tilde = readKey()
      if tilde == 126 {
        pageScroll(up: false, state: &state, fraction: 0.9)
        return
      }
    }
    if next2 == 49 {
      let tilde = readKey()
      if tilde == 126 {
        moveToBeginningOfLine(state: &state)
        return
      }
    }
    if next2 == 52 {
      let tilde = readKey()
      if tilde == 126 {
        moveToEndOfLine(state: &state)
        return
      }
    }

    switch next2 {
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
    default: break
    }
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

func extendSelectionWordForward(state: inout EditorState) {
  let line = state.buffer[state.cursorLine]
  let count = line.count
  if state.cursorColumn >= count {
    if state.cursorLine < state.buffer.count - 1 {
      state.cursorLine += 1
      state.cursorColumn = 0
    }
    return
  }
  let chars = Array(line)
  var i = state.cursorColumn
  let ch = chars[i]
  if isWordCharacter(ch) {
    while i < count && isWordCharacter(chars[i]) { i += 1 }
  } else if ch.isWhitespace {
    while i < count && chars[i].isWhitespace { i += 1 }
  } else {
    while i < count && !isWordCharacter(chars[i]) && !chars[i].isWhitespace { i += 1 }
  }
  state.cursorColumn = i
}

func extendSelectionWordBackward(state: inout EditorState) {
  if state.cursorColumn == 0 {
    if state.cursorLine > 0 {
      state.cursorLine -= 1
      state.cursorColumn = state.buffer[state.cursorLine].count
    }
    return
  }
  let line = state.buffer[state.cursorLine]
  let chars = Array(line)
  var i = state.cursorColumn - 1
  let ch = chars[i]
  if isWordCharacter(ch) {
    while i >= 0 && isWordCharacter(chars[i]) { i -= 1 }
  } else if ch.isWhitespace {
    while i >= 0 && chars[i].isWhitespace { i -= 1 }
  } else {
    while i >= 0 && !isWordCharacter(chars[i]) && !chars[i].isWhitespace { i -= 1 }
  }
  state.cursorColumn = i + 1
}

func pageScroll(up: Bool, state: inout EditorState, fraction: Double = 1.0) {
  let termSize = Terminal.getTerminalSize()
  let contentWidth = max(1, termSize.cols - 6)
  let headerLines = 1
  let footerLines = 2
  let maxVisibleRows = max(1, termSize.rows - headerLines - footerLines)
  let vrows = buildVisualRows(state: state, contentWidth: contentWidth)
  let (curVIndex, curVRow) = findCursorVisualIndex(state: state, rows: vrows)
  let colInRow = max(0, state.cursorColumn - curVRow.start)
  let page = maxVisibleRows
  let frac = max(0.0, min(1.0, fraction))
  let delta = max(1, Int(floor(Double(page) * frac)))
  var newOffset = state.visualScrollOffset
  var newCursorV = curVIndex
  if up {
    newOffset = max(0, newOffset - delta)
    newCursorV = max(0, curVIndex - delta)
  } else {
    let maxOffset = max(0, vrows.count - maxVisibleRows)
    newOffset = min(maxOffset, newOffset + delta)
    newCursorV = min(vrows.count - 1, curVIndex + delta)
  }
  let newRow = vrows[newCursorV]
  let newColInRow = min(colInRow, max(0, newRow.end - newRow.start))
  state.cursorLine = newRow.lineIndex
  state.cursorColumn = newRow.start + newColInRow
  state.clampCursor()
  state.visualScrollOffset = newOffset
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
  let visualRows = buildVisualRows(state: state, contentWidth: contentWidth)
  if visualRows.isEmpty { return false }

  let (currentIndex, currentRow) = findCursorVisualIndex(state: state, rows: visualRows)
  let targetIndex = currentIndex + direction
  if targetIndex < 0 || targetIndex >= visualRows.count { return false }

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
