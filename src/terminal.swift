import Foundation

#if canImport(Darwin)
  import Darwin
#endif

// Terminal control utilities extracted from main for clarity
struct Terminal {
  static let ESC = "\u{1B}"
  static let clearScreen = "\(ESC)[2J"
  static let home = "\(ESC)[H"
  static let hideCursor = "\(ESC)[?25l"
  static let showCursor = "\(ESC)[?25h"
  static let bold = "\(ESC)[1m"
  static let reset = "\(ESC)[0m"
  static let blue = "\(ESC)[34m"
  static let green = "\(ESC)[32m"
  static let pink = "\(ESC)[95m"
  static let grey = "\(ESC)[90m"
  static let yellow = "\(ESC)[33m"
  static let red = "\(ESC)[31m"
  static let white = "\(ESC)[37m"
  static let closeSymbol = "●"
  static let cyan = "\(ESC)[36m"
  static let brightCyan = "\(ESC)[96m"
  static let brightBlack = "\(ESC)[90m"
  static let ansiCyan6 = "\(ESC)[38;5;6m"
  static let ansiBlue12 = "\(ESC)[38;5;12m"
  static let ansiBlue209 = "\(ESC)[38;5;209m"
  // Selection highlight: reverse video to remain visible even when terminals disable custom colors
  static let highlight = "\(ESC)[7m"
  // Subtle scrollbar styling
  static let scrollbarBG = "\(ESC)[48;5;240m"  // dark grey background
  static let scrollbarFG = "\(ESC)[38;5;250m"  // light grey foreground for caps/dots

  // Alternate screen buffer control (like nano/pico)
  static let enterAltScreen = "\(ESC)[?1049h"
  static let exitAltScreen = "\(ESC)[?1049l"

  // Cursor positioning
  static func moveCursor(to row: Int, col: Int) -> String {
    return "\(ESC)[\(row);\(col)H"
  }

  // Cursor shape control
  static let cursorBlinkingBar = "\(ESC)[5 q"  // Blinking vertical bar
  static let cursorSteadyBar = "\(ESC)[6 q"  // Steady vertical bar
  static let cursorRestoreDefault = "\(ESC)[0 q"  // Restore to user's default

  // Cursor color control (experimental - terminal dependent)
  static let cursorColorWhite = "\(ESC)]12;#FFFFFF\(ESC)\\"  // OSC sequence for white cursor
  static let cursorColorPink = "\(ESC)]12;#FF69B4\(ESC)\\"  // OSC sequence for pink cursor
  static let cursorColorBlue = "\(ESC)]12;#4A90E2\(ESC)\\"  // OSC sequence for blue cursor
  static let cursorColorGreen = "\(ESC)]12;#50C878\(ESC)\\"  // OSC sequence for green cursor

  // Mouse support
  static let enableMouseTracking = "\(ESC)[?1000h\(ESC)[?1002h\(ESC)[?1006h"  // Enable mouse click and drag tracking with SGR mode
  static let disableMouseTracking = "\(ESC)[?1006l\(ESC)[?1002l\(ESC)[?1000l"  // Disable mouse tracking
  static let cursorColorReset = "\(ESC)]112\(ESC)\\"  // Reset cursor color to default

  private static var originalTermios: termios?
  private static var rawModeActive = false

  private static func write(_ string: String) {
    let bytes = Array(string.utf8)
    bytes.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      _ = Darwin.write(STDOUT_FILENO, baseAddress, buffer.count)
    }
  }

  static func restoreState() {
    write(disableMouseTracking)
    write(cursorColorReset)
    write(cursorRestoreDefault)
    write(showCursor)
    write(exitAltScreen)
    disableRawMode()
  }

  static func enableRawMode() {
    if rawModeActive { return }

    var current = termios()
    guard tcgetattr(STDIN_FILENO, &current) == 0 else { return }
    originalTermios = current

    var raw = current
    raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
    raw.c_iflag &= ~tcflag_t(IXON | ICRNL)

    if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 {
      rawModeActive = true
    }
  }

  static func disableRawMode() {
    guard rawModeActive else { return }
    if var original = originalTermios {
      tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }
    rawModeActive = false
  }

  static func getTerminalSize() -> (rows: Int, cols: Int) {
    var w = winsize()
    _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &w)
    return (Int(w.ws_row), Int(w.ws_col))
  }

  static func displayWidth(of character: Character) -> Int {
    var width = 0
    for scalar in character.unicodeScalars {
      #if canImport(Darwin)
        let result = Darwin.wcwidth(wint_t(scalar.value))
        if result > 0 { width += Int(result) }
      #else
        width += 1
      #endif
    }

    if width == 0 {
      let scalars = character.unicodeScalars
      if scalars.allSatisfy({ $0.properties.generalCategory == .control }) { return 0 }
      if scalars.allSatisfy({
        switch $0.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .spacingMark: return true
        default: return false
        }
      }) {
        return 0
      }
      return max(1, scalars.isEmpty ? 0 : scalars.count)
    }

    return width
  }

  static func displayWidth(of string: String) -> Int {
    var width = 0
    for character in string {
      width += displayWidth(of: character)
    }
    return width
  }
}
