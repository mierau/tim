import Foundation

#if canImport(Darwin)
  import Darwin
#endif

enum EditorController {
  static func run() {
    var state = EditorState()
    run(state: &state)
  }

  static func run(initialBuffer: [String], filePath: String?, initialCursor: (line: Int, column: Int)? = nil) {
    var state = EditorState()
    state.buffer = initialBuffer
    state.filePath = filePath
    if let cursor = initialCursor {
      state.cursorLine = cursor.line
      state.cursorColumn = cursor.column
      state.clampCursor()
    }
    run(state: &state)
  }

  static func run(state: inout EditorState) {
    var editorState = state
    var running = true

    var sessionActive = false

    func cleanup() {
      guard sessionActive else { return }
      sessionActive = false
      Terminal.restoreState()
    }

    TerminalSignalGuard.install(cleanup: cleanup)

    signal(SIGTSTP) { _ in }

    Terminal.enableRawMode()
    sessionActive = true
    print(Terminal.enterAltScreen, terminator: "")
    print(Terminal.showCursor, terminator: "")
    print(Terminal.cursorSteadyBar, terminator: "")
    print(Terminal.cursorColorPink, terminator: "")
    print(Terminal.enableMouseTracking, terminator: "")

    defer { TerminalSignalGuard.performCleanup() }

    while running {
      editorState.updateCursorBlink()
      if editorState.needsRedraw {
        drawEditor(state: &editorState)
        editorState.needsRedraw = false
      }
      while true {
        let key = readKeyWithTimeout()
        if key == -1 { break }
        editorState.needsRedraw = true
        switch key {
        case 17: running = false
        case 3: copySelection(state: &editorState)
        case 24: cutSelection(state: &editorState)
        case 22: pasteClipboard(state: &editorState)
        case 13, 10: insertNewline(state: &editorState)
        case 127, 8: backspace(state: &editorState)
        case 9: insertTab(state: &editorState)
        case 1: selectAll(state: &editorState)
        case 5: moveToEndOfLine(state: &editorState)
        case 11: deleteToEndOfLine(state: &editorState)
        case 2: moveToBeginningOfLine(state: &editorState)
        case 26: break
        case 23: smartDeleteBackward(state: &editorState)
        case 21: selectLineUp(state: &editorState)
        case 4: selectLineDown(state: &editorState)
        case 27: handleEscapeSequence(state: &editorState)
        default:
          if key >= 32 && key <= 126 {
            let char = Character(UnicodeScalar(key)!)
            if char == "[" {
              let nextKey = readKeyWithTimeout()
              if nextKey == 65 || nextKey == 66 || nextKey == 67 || nextKey == 68 {
                continue
              } else if nextKey != -1 {
                insertCharacter(char, state: &editorState)
                insertCharacter(Character(UnicodeScalar(nextKey)!), state: &editorState)
              } else {
                insertCharacter(char, state: &editorState)
              }
            } else {
              insertCharacter(char, state: &editorState)
            }
          }
        }
      }
      usleep(16000)
    }
  }
}

private enum TerminalSignalGuard {
  private static var installed = false
  private static var cleanup: (() -> Void)?
  private static var cleanedUp = false

  private static let atexitHandler: @convention(c) () -> Void = {
    performCleanup()
  }

  private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
    performCleanup()
    switch sig {
    case SIGINT, SIGTERM, SIGQUIT:
      _Exit(128 + sig)
    default:
      signal(sig, SIG_DFL)
      raise(sig)
    }
  }

  static func install(cleanup: @escaping () -> Void) {
    self.cleanup = cleanup
    cleanedUp = false

    if !installed {
      installed = true
      atexit(atexitHandler)
      registerSignals()
    }
  }

  static func performCleanup() {
    guard !cleanedUp else { return }
    cleanedUp = true
    cleanup?()
  }

  private static func registerSignals() {
    let signalsToHandle: [Int32] = [SIGINT, SIGTERM, SIGQUIT, SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE]
    for sig in signalsToHandle {
      signal(sig, signalHandler)
    }
  }
}
