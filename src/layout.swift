import Foundation

struct VisualRow {
  let lineIndex: Int
  let start: Int
  let end: Int
  let isFirst: Bool
  let isEndOfLine: Bool
}

func wrapLineIndices(_ line: String, width: Int) -> [Int] {
  let count = line.count
  if width <= 0 { return [0, count] }
  if count == 0 { return [0, 0] }

  var indices: [Int] = [0]
  let chars = Array(line)
  var pos = 0
  while pos < chars.count {
    let remaining = chars.count - pos
    if remaining <= width {
      indices.append(chars.count)
      break
    }
    let breakPos = pos + width
    var i = breakPos
    while i > pos && !chars[i - 1].isWhitespace { i -= 1 }
    if i == pos {
      indices.append(pos + width)
      pos += width
    } else {
      indices.append(i)
      pos = i
    }
  }
  if indices.last != chars.count { indices.append(chars.count) }
  if indices.count < 2 { indices.append(0) }
  return indices
}

func buildVisualRows(state: EditorState, contentWidth: Int) -> [VisualRow] {
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
