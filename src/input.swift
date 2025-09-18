import Foundation

let doubleClickThreshold: TimeInterval = 0.3

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
  var char: Int8 = 0
  let result = read(STDIN_FILENO, &char, 1)
  if result > 0 {
    return Int(char)
  } else {
    return -1  // No data available
  }
}

func readKeyWithTimeout() -> Int {
  // Set stdin to non-blocking mode temporarily
  let flags = fcntl(STDIN_FILENO, F_GETFL)
  let _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)

  var char: Int8 = 0
  let result = read(STDIN_FILENO, &char, 1)

  // Restore blocking mode
  let _ = fcntl(STDIN_FILENO, F_SETFL, flags)

  return result > 0 ? Int(char) : -1
}
