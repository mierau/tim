import Foundation

enum ScrollbarHit { case above, handle, below }

struct Scrollbar {
  static func compute(totalRows: Int, trackHeight: Int, offset: Int) -> (
    start: Int, height: Int, maxOffset: Int
  ) {
    if trackHeight <= 0 { return (0, 0, 0) }
    let clampedRows = max(0, totalRows)
    if clampedRows == 0 || clampedRows <= trackHeight { return (0, 0, 0) }

    let visible = min(trackHeight, clampedRows)
    var height = visible
    let maxOffset = max(0, totalRows - trackHeight)
    if totalRows > trackHeight {
      height = max(1, Int(Double(trackHeight) * Double(trackHeight) / Double(totalRows)))
    }
    let denom = max(1, trackHeight - height)
    let start =
      (maxOffset == 0)
      ? 0 : Int(round(Double(min(maxOffset, max(0, offset))) / Double(maxOffset) * Double(denom)))
    return (start, height, maxOffset)
  }

  static func hitTest(localRow: Int, start: Int, height: Int) -> ScrollbarHit {
    let end = start + height - 1
    if localRow < start { return .above }
    if localRow > end { return .below }
    return .handle
  }

  static func pageStep(trackHeight: Int, fraction: Double) -> Int {
    let frac = max(0.0, min(1.0, fraction))
    return max(1, Int(floor(Double(max(0, trackHeight)) * frac)))
  }
}
