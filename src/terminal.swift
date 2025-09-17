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
    var raw = termios()
    tcgetattr(STDIN_FILENO, &raw)
    raw.c_lflag &= ~UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
  }

  static func disableRawMode() {
    var cooked = termios()
    tcgetattr(STDIN_FILENO, &cooked)
    cooked.c_lflag |= UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &cooked)
  }

  static func getTerminalSize() -> (rows: Int, cols: Int) {
    var w = winsize()
    _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &w)
    return (Int(w.ws_row), Int(w.ws_col))
  }
}
