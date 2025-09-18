import Foundation

struct VisualRow {
  let lineIndex: Int
  let start: Int
  let end: Int
  let isFirst: Bool
  let isEndOfLine: Bool
}

struct LayoutCache {
  private(set) var cachedRows: [VisualRow] = []
  private var cachedWidth: Int = -1
  private var cachedGeneration: Int = -1

  mutating func invalidate() {
    cachedGeneration = -1
  }

  mutating func visualRows(for state: EditorState, contentWidth: Int) -> [VisualRow] {
    guard contentWidth > 0 else {
      cachedRows = []
      cachedWidth = contentWidth
      cachedGeneration = state.layoutGeneration
      return cachedRows
    }

    if cachedWidth != contentWidth || cachedGeneration != state.layoutGeneration {
      cachedRows = computeVisualRows(state: state, contentWidth: contentWidth)
      cachedWidth = contentWidth
      cachedGeneration = state.layoutGeneration
    }
    return cachedRows
  }
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

func computeVisualRows(state: EditorState, contentWidth: Int) -> [VisualRow] {
  var rows: [VisualRow] = []
  for (li, line) in state.buffer.enumerated() {
    let cuts = wrapLineIndices(line, width: contentWidth)
    if cuts.count < 2 {
      rows.append(VisualRow(lineIndex: li, start: 0, end: 0, isFirst: true, isEndOfLine: true))
      continue
    }
    for ci in 0..<(cuts.count - 1) {
      let start = cuts[ci]
      let end = cuts[ci + 1]
      let isFirst = (ci == 0)
      let isEnd = (ci == cuts.count - 2)
      rows.append(
        VisualRow(lineIndex: li, start: start, end: end, isFirst: isFirst, isEndOfLine: isEnd))
    }
  }
  if rows.isEmpty {
    rows.append(VisualRow(lineIndex: 0, start: 0, end: 0, isFirst: true, isEndOfLine: true))
  }
  return rows
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
