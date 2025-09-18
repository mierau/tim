import Foundation

struct VisualRow {
  let lineIndex: Int
  let start: Int
  let end: Int
  let isFirst: Bool
  let isEndOfLine: Bool
}

struct LayoutCache {
  private struct LineSpan {
    var start: Int
    var count: Int
  }

  private var contentWidth: Int = -1
  private var rows: [VisualRow] = []
  private var spans: [LineSpan] = []
  private var dirtyLines: Set<Int> = []

  mutating func invalidateAll() {
    rows.removeAll(keepingCapacity: true)
    spans.removeAll(keepingCapacity: true)
    dirtyLines.removeAll(keepingCapacity: true)
    contentWidth = -1
  }

  mutating func invalidateLines(in range: Range<Int>) {
    if range.isEmpty { return }
    for line in range {
      dirtyLines.insert(line)
    }
  }

  mutating func visualRows(for state: EditorState, contentWidth: Int) -> [VisualRow] {
    guard contentWidth > 0 else {
      invalidateAll()
      return []
    }

    if self.contentWidth != contentWidth || spans.count != state.buffer.count {
      rebuildAll(state: state, width: contentWidth)
      return rows
    }

    if !dirtyLines.isEmpty {
      rebuildDirtyLines(state: state, width: contentWidth)
    }

    return rows
  }

  private mutating func rebuildAll(state: EditorState, width: Int) {
    rows.removeAll(keepingCapacity: true)
    spans.removeAll(keepingCapacity: true)
    spans.reserveCapacity(state.buffer.count)

    var startIndex = 0
    for (lineIndex, line) in state.buffer.enumerated() {
      let lineRows = makeRows(for: line, lineIndex: lineIndex, width: width)
      rows.append(contentsOf: lineRows)
      spans.append(LineSpan(start: startIndex, count: lineRows.count))
      startIndex += lineRows.count
    }

    contentWidth = width
    dirtyLines.removeAll(keepingCapacity: true)
  }

  private mutating func rebuildDirtyLines(state: EditorState, width: Int) {
    let sortedLines = dirtyLines.sorted()
    dirtyLines.removeAll(keepingCapacity: true)

    for lineIndex in sortedLines {
      guard lineIndex >= 0, lineIndex < state.buffer.count, lineIndex < spans.count else {
        rebuildAll(state: state, width: width)
        return
      }

      let oldSpan = spans[lineIndex]
      let newRows = makeRows(for: state.buffer[lineIndex], lineIndex: lineIndex, width: width)

      let delta = newRows.count - oldSpan.count

      if oldSpan.count > 0 {
        rows.removeSubrange(oldSpan.start..<(oldSpan.start + oldSpan.count))
      }
      if !newRows.isEmpty {
        rows.insert(contentsOf: newRows, at: oldSpan.start)
      }

      spans[lineIndex] = LineSpan(start: oldSpan.start, count: newRows.count)

      if delta != 0 {
        for idx in (lineIndex + 1)..<spans.count {
          spans[idx].start += delta
        }
      }
    }
  }
}

private func makeRows(for line: String, lineIndex: Int, width: Int) -> [VisualRow] {
  let cuts = wrapLineIndices(line, width: width)
  if cuts.count < 2 {
    return [VisualRow(lineIndex: lineIndex, start: 0, end: 0, isFirst: true, isEndOfLine: true)]
  }
  var result: [VisualRow] = []
  result.reserveCapacity(max(1, cuts.count - 1))
  for ci in 0..<(cuts.count - 1) {
    let start = cuts[ci]
    let end = cuts[ci + 1]
    let isFirst = (ci == 0)
    let isEnd = (ci == cuts.count - 2)
    result.append(VisualRow(lineIndex: lineIndex, start: start, end: end, isFirst: isFirst, isEndOfLine: isEnd))
  }
  return result
}

func wrapLineIndices(_ line: String, width: Int) -> [Int] {
  let count = line.count
  if width <= 0 { return [0, count] }
  if count == 0 { return [0, 0] }

  var indices: [Int] = [0]
  let chars = Array(line)
  let widths = chars.map { max(0, Terminal.displayWidth(of: $0)) }
  let displayWidth = widths.reduce(0, +)
  if displayWidth <= width {
    indices.append(chars.count)
    return indices
  }
  var pos = 0

  while pos < chars.count {
    var currentWidth = 0
    var lastBreak: Int?
    var idx = pos

    while idx < chars.count {
      let charWidth = widths[idx]
      if currentWidth + charWidth > width {
        if currentWidth == 0 {
          idx += 1
        }
        break
      }

      currentWidth += charWidth
      if chars[idx].isWhitespace { lastBreak = idx + 1 }
      idx += 1

      if currentWidth >= width { break }
    }

    if idx >= chars.count {
      indices.append(chars.count)
      break
    }

    if let breakIndex = lastBreak, breakIndex > pos {
      indices.append(breakIndex)
      pos = breakIndex
    } else if idx > pos {
      indices.append(idx)
      pos = idx
    } else {
      indices.append(pos + 1)
      pos += 1
    }
  }

  if indices.last != chars.count { indices.append(chars.count) }
  if indices.count < 2 { indices.append(0) }
  return indices
}

func findCursorVisualIndex(state: EditorState, rows: [VisualRow]) -> (index: Int, row: VisualRow) {
  for (i, r) in rows.enumerated() {
    if r.lineIndex == state.cursorLine {
      let upperBoundExclusive = r.end
      let inRange: Bool
      if r.isEndOfLine {
        inRange = state.cursorColumn >= r.start && state.cursorColumn <= upperBoundExclusive
      } else {
        inRange = state.cursorColumn >= r.start && state.cursorColumn < upperBoundExclusive
      }
      if inRange { return (i, r) }
    }
  }
  for (i, r) in rows.enumerated() where r.lineIndex == state.cursorLine {
    return (i, r)
  }
  return (0, rows[0])
}
