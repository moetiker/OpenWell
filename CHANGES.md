# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
except that the first subsection is called `New` rather than `Added`. The release
workflow matches on `### New`; renaming it silently drops the section from the
release notes.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### New

### Changed

### Fixed
- `brew upgrade` quits OpenWell and starts the new version, which then opened a terminal window as if the Dock icon had been clicked. A start within a minute of a quit requested by another program now opens no window.

## 0.1.1 - 2026-11-03
### Fixed
- After a call of `OpenWell --spot`, such as Cmd+N with the WezTerm binding and often right after login, the Dock showed OpenWell as not running: no dot under the icon, no menu on a right click, and a click opened no window. `OpenWell --spot` now leaves the Dock state alone, whichever terminal or script calls it.

## 0.1.0 - 2026-11-01
### New
- OpenWell, a Dock app that opens terminal windows on a free spot of the screen. A Dock click opens a window in the chosen terminal, and Cmd+N in WezTerm, iTerm2 or Terminal gets the same placement.
- The menus and messages follow the language of the desktop: English, German, French, Italian or Spanish. Other languages show English.
