import Foundation

let doubleClickThreshold: TimeInterval = 0.3

private var pendingBytes: [UInt8] = []

struct MouseEvent {
  let button: Int
  let x: Int
  let y: Int
  let isPress: Bool
  let modifiers: Int

  var hasShift: Bool { (modifiers & 4) != 0 }
}

func parseMouseEvent() -> MouseEvent? {
  // Read the rest of the mouse sequence: ESC[<button;x;y[mM]
  // Note: handleEscapeSequence has already consumed ESC, '[' and '<'.
  // Seed the buffer with '<' so parsing logic matches SGR format.
  var sequence = "<"

  // We already read ESC and [, now read until we get 'm' or 'M'
  while true {
    let char = readKeyWithTimeout()
    if char == -1 { return nil }

    let character = Character(UnicodeScalar(char)!)
    sequence.append(character)

    if character == "m" || character == "M" {
      break
    }
  }

  // Parse the sequence like "<0;45;12m" or "<0;45;12M"
  if sequence.hasPrefix("<") && (sequence.hasSuffix("m") || sequence.hasSuffix("M")) {
    let isPress = sequence.hasSuffix("M")
    let content = String(sequence.dropFirst().dropLast())  // Remove < and m/M
    let parts = content.split(separator: ";")

    if parts.count == 3,
      let rawButton = Int(parts[0]),
      let x = Int(parts[1]),
      let y = Int(parts[2])
    {
      let modifiers = rawButton & 0b11100
      return MouseEvent(button: rawButton, x: x, y: y, isPress: isPress, modifiers: modifiers)
    }
  }

  return nil
}

func readKey() -> Int {
  if !pendingBytes.isEmpty {
    return Int(pendingBytes.removeFirst())
  }
  var byte: UInt8 = 0
  let result = read(STDIN_FILENO, &byte, 1)
  if result > 0 {
    return Int(byte)
  } else {
    return -1  // No data available
  }
}

func readKeyWithTimeout() -> Int {
  if !pendingBytes.isEmpty {
    return Int(pendingBytes.removeFirst())
  }
  // Set stdin to non-blocking mode temporarily
  let flags = fcntl(STDIN_FILENO, F_GETFL)
  let _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)

  var byte: UInt8 = 0
  let result = read(STDIN_FILENO, &byte, 1)

  // Restore blocking mode
  let _ = fcntl(STDIN_FILENO, F_SETFL, flags)

  return result > 0 ? Int(byte) : -1
}

func peekKeyWithTimeout() -> Int {
  let value = readKeyWithTimeout()
  if value != -1 {
    let clamped = UInt8(truncatingIfNeeded: value)
    pendingBytes.insert(clamped, at: 0)
  }
  return value
}

func decodeInputCharacter(startingWith value: Int) -> Character? {
  guard value >= 0 && value <= 255 else { return nil }
  let firstByte = UInt8(value)
  if firstByte < 0x80 {
    return Character(UnicodeScalar(firstByte))
  }

  guard let expectedCount = expectedContinuationBytes(firstByte: firstByte) else {
    return nil
  }

  var bytes: [UInt8] = [firstByte]
  for _ in 0..<expectedCount {
    guard let continuation = readContinuationByte() else {
      pendingBytes.insert(contentsOf: bytes.reversed(), at: 0)
      return nil
    }
    bytes.append(continuation)
  }

  var iterator = bytes.makeIterator()
  var utf8Decoder = UTF8()
  switch utf8Decoder.decode(&iterator) {
  case .scalarValue(let scalar):
    return Character(scalar)
  case .emptyInput, .error:
    return nil
  }
}

private func expectedContinuationBytes(firstByte: UInt8) -> Int? {
  switch firstByte {
  case 0xC2...0xDF: return 1
  case 0xE0...0xEF: return 2
  case 0xF0...0xF4: return 3
  default: return nil
  }
}

private func readContinuationByte() -> UInt8? {
  let nextValue = readKey()
  guard nextValue >= 0 && nextValue <= 255 else { return nil }
  let byte = UInt8(nextValue)
  guard byte >= 0x80 && byte <= 0xBF else {
    pendingBytes.insert(byte, at: 0)
    return nil
  }
  return byte
}
