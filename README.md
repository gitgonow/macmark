# MacMark

MacMark is an open source Markdown editor for macOS, released under the MIT License. It is a modernized fork of the original [MacDownApp/macdown](https://github.com/MacDownApp/macdown), updated to run natively on Apple Silicon (ARM64) with modern macOS.

![screenshot](assets/screenshot.png)

## What's New in 2.0

- **Native Apple Silicon support** — runs as a native ARM64 binary, no Rosetta required
- **macOS 11+ deployment target** — drops legacy 10.8 support, uses modern APIs
- **ARM64 crash fix** — toolbar button actions now work correctly on Apple Silicon
- **List interruption** — bullet and ordered lists no longer require a blank line before them
- **Modern APIs** — deprecated AppKit and Foundation APIs replaced throughout

## Install

Build from source using Xcode (see below).

## Building

### Requirements

- macOS 11.0 or later
- Xcode 12 or later
- [CocoaPods](https://cocoapods.org) (`brew install cocoapods`)

### Steps

```bash
git clone --recursive https://github.com/gitgonow/macmark.git
cd macmark
pod install
open MacDown.xcworkspace
```

Then build and run the **MacDown** scheme in Xcode.

## Features

- Live split-pane Markdown preview
- Syntax highlighting in code blocks (via Prism)
- Multiple editor themes
- GitHub Flavored Markdown support
- MathJax support
- Customizable styles and themes

## License

MacMark is released under the MIT License. See the `LICENSE` directory for full license text, including third-party component licenses.

The following editor themes and CSS files are courtesy of [Chen Luo](https://twitter.com/chenluois)'s [Mou](http://mouapp.com):

- Mou Fresh Air / Mou Night / Mou Paper (and variants)
- Tomorrow / Tomorrow Blue / Tomorrow+
- Writer / Writer+
- Clearness / Clearness Dark
- GitHub / GitHub2

## Original Project

This is a fork of [MacDownApp/macdown](https://github.com/MacDownApp/macdown). Visit the original project for history and prior releases.
