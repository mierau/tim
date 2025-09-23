# tim

The Mac-friendly command line text editor.

## Features
- Clean simple interface.
- Select text using Mac keyboard shortcuts.
- Copy/paste/cut support through `^C`/`^V`/`^X` (reads and writes to system clipboard).
- Undo/redo support through `^Z`/`^Y`.
- Documents have an edited marker when they've been edited but not saved.
- Save new or edited documents with ctrl-s.
- Use a mouse or trackpad to select with single, double, or triple-click selection.
- Use a trackpad and scroll wheel to scroll long documents.
- Proportional scrollbar you can drag to scroll around a document.
- Automatic line wrapping.
- Indentation preservation when moving to a new line.
- Automatic detection of binary files.
- Status footer with live line/column counts and selection summaries.
- Looks great in with or without terminal colors.
- Mac-like `^Q` shortcut to quit.
- Open documents over HTTP(S).
- Open text-friendly versions of Wikipedia articles.
- Open RSS/Atom feeds and Bluesky profiles as readable plain text.
- Incremental find (`⌃F`) with next/previous (`⌃G`/`⌃R`) and optional `/regex/` search.

## Installation
1. Ensure Xcode command line tools or a Swift 5.9+ toolchain is installed.
2. Clone this repository.
3. Build the CLI:
   ```sh
   swift build
   ```
   Add `-c release` for a release optimized build.

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

Open a file over http(s):
```sh
tim https://web.site/document.html
```

Open a text-friendly Wikipedia article:
Option: -w or --wikipedia
```sh
tim -w albert einstein
```

Open an RSS or Atom feed:
Option: -r or --rss
```sh
tim -r https://example.com/feed.xml
```

Open a Bluesky user's public feed:
Option -b or --bluesky
```sh
tim -b mierau.bsky.social
```

Additional flags:
- `tim --help` prints the available options.
- `tim --version` shows the current release tag.
- `tim -` reads buffer contents from standard input (ASCII or UTF-8 text only).
- `tim -r <url>` downloads and formats an RSS/Atom feed.
- `tim -b <handle>` fetches a Bluesky profile feed by handle, DID, or profile URL.
- Use `--` before a path that begins with `-` to treat it literally.

Find within the current buffer with `⌃F`, advance matches with `⌃G`, move backward with `⌃R`, and press `Esc` (or `⌃F` a second time) to close. After opening the prompt, pressing `⌃F` moves focus to the document so subsequent typing edits the buffer; run `⌃F` once more to exit. Surround the query with `/` characters to run a regular expression, e.g. `/^[A-Z].*/`.

## Project Layout
- `src/app.swift` bootstraps CLI parsing, file loading, and Wikipedia/HTTP entry points
- `src/editorcontroller.swift` orchestrates the main render loop and terminal lifetime
- `src/editorstate.swift` tracks buffer, cursor/selection state, undo stacks, and layout cache metadata
- `src/actions.swift` applies text mutations, clipboard, and selection helpers
- `src/layout.swift` wraps logical lines into visual rows (cached per terminal width)
- `src/renderer.swift` draws the editor frame, gutter, status footer, and cursor
- `src/input.swift`, `src/keys.swift`, `src/mouse.swift` decode keyboard/mouse events and route them to actions
- `src/terminal.swift` and `src/scrollbar.swift` emit escape codes and scrollbar math
- `src/http.swift` implements the synchronous URLSession helpers used across the app
- `src/wikipedia.swift` and `src/bluesky.swift` fetch rich text sources and normalize them to plain-text buffers
- `src/rss.swift` parses RSS/Atom feeds into timeline entries
- `src/clipboard.swift` bridges to `pbcopy`/`pbpaste` for macOS clipboard integration

## License
This project is available under the terms of the [MIT License](LICENSE).
