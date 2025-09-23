import Foundation

struct VisualRow {
  let lineIndex: Int
  let start: Int
  let end: Int
  let isFirst: Bool
  let isEndOfLine: Bool
}

struct LayoutCache {
  struct Snapshot {
    let rows: [VisualRow]
    let lineOffsets: [Int]
  }

  private var perLineRows: [[VisualRow]] = []
  private var flattenedRows: [VisualRow] = []
  private var lineStartOffsets: [Int] = []
  private var dirtyLines = IndexSet()
  private var cachedWidth: Int = -1
  private var cachedLineCount: Int = 0

  mutating func invalidateAll() {
    perLineRows.removeAll(keepingCapacity: false)
    flattenedRows.removeAll(keepingCapacity: false)
    lineStartOffsets.removeAll(keepingCapacity: false)
    dirtyLines.removeAll()
    cachedWidth = -1
    cachedLineCount = 0
  }

  mutating func invalidateLines(in range: Range<Int>, totalLines: Int) {
    guard !range.isEmpty else { return }
    if cachedWidth == -1 {
      return
    }

    if cachedLineCount != totalLines {
      cachedLineCount = totalLines
      perLineRows = Array(repeating: [], count: totalLines)
      lineStartOffsets = Array(repeating: 0, count: totalLines)
      flattenedRows.removeAll(keepingCapacity: false)
      dirtyLines = IndexSet(integersIn: 0..<totalLines)
      return
    }

    if perLineRows.count != totalLines {
      perLineRows = Array(repeating: [], count: totalLines)
    }
    if lineStartOffsets.count != totalLines {
      lineStartOffsets = Array(repeating: 0, count: totalLines)
    }

    let clampedLower = max(0, range.lowerBound)
    let clampedUpper = min(totalLines, range.upperBound)
    guard clampedLower < clampedUpper else { return }
    dirtyLines.insert(integersIn: clampedLower..<clampedUpper)
  }

  mutating func snapshot(for state: EditorState, contentWidth: Int) -> Snapshot {
    let lineCount = state.buffer.count

    guard contentWidth > 0 else {
      flattenedRows = []
      perLineRows = Array(repeating: [], count: lineCount)
      lineStartOffsets = Array(repeating: 0, count: lineCount)
      cachedWidth = contentWidth
      cachedLineCount = lineCount
      return Snapshot(rows: flattenedRows, lineOffsets: lineStartOffsets)
    }

    if cachedWidth != contentWidth {
      cachedWidth = contentWidth
      cachedLineCount = lineCount
      rebuildAll(buffer: state.buffer, width: contentWidth)
    } else if cachedLineCount != lineCount {
      cachedLineCount = lineCount
      rebuildAll(buffer: state.buffer, width: contentWidth)
    } else {
      ensureStorage(for: lineCount)
      if flattenedRows.isEmpty && lineCount > 0 {
        rebuildAll(buffer: state.buffer, width: contentWidth)
      } else if !dirtyLines.isEmpty {
        updateDirtyLines(buffer: state.buffer, width: contentWidth)
        dirtyLines.removeAll()
      }
    }

    if flattenedRows.isEmpty {
      flattenedRows = [VisualRow(lineIndex: 0, start: 0, end: 0, isFirst: true, isEndOfLine: true)]
      lineStartOffsets = []
    }

    return Snapshot(rows: flattenedRows, lineOffsets: lineStartOffsets)
  }

  private mutating func ensureStorage(for lineCount: Int) {
    if lineCount == 0 {
      perLineRows = []
      lineStartOffsets = []
      return
    }
    if perLineRows.count != lineCount {
      perLineRows = Array(repeating: [], count: lineCount)
    }
    if lineStartOffsets.count != lineCount {
      lineStartOffsets = Array(repeating: 0, count: lineCount)
    }
  }

  private mutating func rebuildAll(buffer: [String], width: Int) {
    let lineCount = buffer.count
    ensureStorage(for: lineCount)

    flattenedRows.removeAll(keepingCapacity: true)
    lineStartOffsets.removeAll(keepingCapacity: true)
    lineStartOffsets.reserveCapacity(lineCount)

    var runningIndex = 0
    for (idx, line) in buffer.enumerated() {
      lineStartOffsets.append(runningIndex)
      let rows = makeRows(for: line, lineIndex: idx, width: width)
      perLineRows[idx] = rows
      flattenedRows.append(contentsOf: rows)
      runningIndex += rows.count
    }

    if lineCount == 0 {
      perLineRows = []
      lineStartOffsets = []
      flattenedRows = []
    }
    dirtyLines.removeAll()
  }

  private mutating func updateDirtyLines(buffer: [String], width: Int) {
    guard !dirtyLines.isEmpty else { return }
    ensureStorage(for: buffer.count)
    let sorted = dirtyLines.sorted()

    for idx in sorted {
      guard idx >= 0, idx < buffer.count else { continue }
      let line = buffer[idx]
      let oldRows = perLineRows[idx]
      let oldCount = oldRows.count
      let newRows = makeRows(for: line, lineIndex: idx, width: width)
      perLineRows[idx] = newRows

      let startIndex = idx < lineStartOffsets.count ? lineStartOffsets[idx] : flattenedRows.count
      let endIndex = startIndex + oldCount
      if startIndex <= flattenedRows.count && endIndex <= flattenedRows.count {
        flattenedRows.replaceSubrange(startIndex..<endIndex, with: newRows)
      }

      let delta = newRows.count - oldCount
      if delta != 0 {
        for offsetIndex in (idx + 1)..<lineStartOffsets.count {
          lineStartOffsets[offsetIndex] += delta
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

func findCursorVisualIndex(state: EditorState, snapshot: LayoutCache.Snapshot) -> (index: Int, row: VisualRow) {
  let rows = snapshot.rows
  guard !rows.isEmpty else {
    let fallback = VisualRow(lineIndex: 0, start: 0, end: 0, isFirst: true, isEndOfLine: true)
    return (0, fallback)
  }

  let cursorLine = max(0, min(state.cursorLine, state.buffer.count - 1))
  let offsets = snapshot.lineOffsets

  if cursorLine < offsets.count {
    let startIndex = offsets[cursorLine]
    let endIndex = (cursorLine + 1) < offsets.count ? offsets[cursorLine + 1] : rows.count
    if startIndex < endIndex {
      for i in startIndex..<endIndex {
        let r = rows[i]
        let upperBoundExclusive = r.end
        let inRange: Bool
        if r.isEndOfLine {
          inRange = state.cursorColumn >= r.start && state.cursorColumn <= upperBoundExclusive
        } else {
          inRange = state.cursorColumn >= r.start && state.cursorColumn < upperBoundExclusive
        }
        if inRange { return (i, r) }
      }
      return (startIndex, rows[startIndex])
    }
  }

  if let matchIndex = rows.enumerated().first(where: { $0.element.lineIndex == cursorLine })?.offset {
    return (matchIndex, rows[matchIndex])
  }

  return (0, rows[0])
}
