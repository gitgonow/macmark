# MacMark

MacMark is a modernized fork of [MacDown](https://github.com/MacDownApp/macdown), the open source Markdown editor for macOS. It brings MacDown up to date with current Apple platforms, development tools, and best practices — while preserving everything that made the original great.

![screenshot](assets/screenshot.png)

## What's Different from MacDown

MacMark is built on the same foundation as MacDown but updated throughout:

| Area | MacDown | MacMark |
|------|---------|---------|
| Architecture | x86_64 only | Universal (arm64 + x86_64) |
| macOS target | 10.8+ | 11.0+ |
| Auto-updater | Sparkle 1.x | Removed (no update server needed) |
| Dependency manager | CocoaPods (legacy pins) | CocoaPods (updated versions) |
| Deprecated APIs | `NSFileHandlingPanelOKButton`, `disableFlushWindow`, `NSKeyedUnarchiver` (legacy), `allowedFileTypes` | Replaced with modern equivalents |
| ARM64 toolbar crash | Present | Fixed |
| List interruption | Requires blank line before lists | Lists interrupt paragraphs correctly |

## Features

- Live split-pane Markdown preview
- Syntax highlighting in code blocks (via Prism)
- GitHub Flavored Markdown support (tables, task lists, strikethrough, fenced code)
- MathJax support for math rendering
- Multiple editor themes and preview styles
- Customizable fonts, key bindings, and rendering options
- Table of contents generation
- PlugIn support

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

## License

MacMark is released under the MIT License. See the `LICENSE` directory for full license text, including third-party component licenses.

The following editor themes and CSS files are courtesy of [Chen Luo](https://twitter.com/chenluois)'s [Mou](http://mouapp.com):

- Mou Fresh Air / Mou Night / Mou Paper (and variants)
- Tomorrow / Tomorrow Blue / Tomorrow+
- Writer / Writer+
- Clearness / Clearness Dark
- GitHub / GitHub2

## Original Project

MacMark is a fork of [MacDownApp/macdown](https://github.com/MacDownApp/macdown) by Tzu-ping Chung. Visit the original project for history and prior releases.
