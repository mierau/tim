# tim

The Mac-friendly command line text editor.

## Features
- Clean simple interface.
- Select text using Mac keyboard shortcuts.
- Copy/paste/cut support through ctrl-c/v/x (reads and writes to system clipboard).
- Use a mouse or trackpad to select with single, double, or triple-click selection.
- Use a trackpad and scroll wheel to scroll long documents.
- Proportional scrollbar you can drag to scroll around a document.
- Automatic line wrapping.
- Indentation preservation when moving to a new line.
- Automatic detection of binary files.
- Status footer with live line/column counts and selection summaries.
- Looks great in with or without terminal colors.
- Mac-like ctrl-q shortcut to quit.

## Installation
1. Ensure Xcode command line tools or a Swift 5.9+ toolchain is installed.
2. Clone this repository.
3. Build the CLI:
   ```sh
   swift build
   ```
   Add `-c release` for optimized profiling builds.

## Usage
Open `tim` without arguments to start with an empty buffer:
```sh
tim
```

Open a file, optionally jumping to a specific line:
```sh
tim path/to/file
tim path/to/file:+42
tim +42 path/to/file
```

Additional flags:
- `tim --help` prints the available options.
- `tim --version` shows the current release tag.
- `tim -` reads buffer contents from standard input (ASCII or UTF-8 text only).
- Use `--` before a path that begins with `-` to treat it literally.

## Project Layout
- `src/app.swift` bootstraps argument parsing and file loading
- `src/editorcontroller.swift` orchestrates the main render loop
- `src/editorstate.swift` tracks buffer, cursor, selection, and scroll state
- `src/actions.swift` applies editing actions from keyboard and mouse events
- `src/layout.swift` wraps logical lines into visual rows
- `src/renderer.swift` handles drawing, gutter styling, and status footer output
- `src/input.swift`, `src/keys.swift`, `src/mouse.swift` decode device input
- `src/terminal.swift` and `src/scrollbar.swift` manage escape sequences and gutter math

## License
This project is available under the terms of the [MIT License](LICENSE).
