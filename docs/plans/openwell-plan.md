# OpenWell plan

OpenWell is a macOS Dock app that opens terminal windows and places every new
terminal window on a free spot of the screen.

## Behaviour

- **Dock click:** a click on the OpenWell icon opens a new window in the chosen
  terminal (default: WezTerm), also when the terminal is already running. If
  the terminal is not running, OpenWell launches it.
- **Cmd+N in the terminal:** OpenWell watches the managed terminal apps through
  the Accessibility API (`kAXWindowCreatedNotification`) and moves new windows
  to a free spot (see "Which windows are placed"). The terminal needs no
  configuration for this, but the move shows as a short jump; see "Windows
  without a jump" for WezTerm.
- **Cmd+N in OpenWell:** when OpenWell itself is frontmost, Cmd+N does the same
  as a Dock click.
- **Login start:** when OpenWell is started as a login item
  (`keyAELaunchedAsLogInItem`, as in MountWell), it opens no window and only
  starts watching. A manual start or a Dock click opens a window.
- **Dock menu:** "New Tab" (Cmd+T in the chosen terminal), "Terminal: <chosen>" with a submenu of the
  installed terminals (icon, check mark on the chosen one), "Open at Login" (via `SMAppService`) and "Edit
  Config". Choosing a terminal writes `terminal` to the config.

## Terminals

- **Discovery:** the apps macOS lists for opening `public.unix-executable`.
  On the development machine this returned exactly WezTerm, iTerm and
  Terminal; shell scripts list TextEdit and browsers as well, `ssh://` misses
  WezTerm.
- **Known list:** WezTerm, iTerm, Terminal, Ghostty, kitty, Alacritty, Warp,
  Hyper, Tabby and Rio by bundle ID, for a terminal that registers for no
  executable type. Only the first three IDs are verified.
- **Menu:** the installed known terminals, then configured and discovered ones.
- **Managed:** `manage` from the config plus every discovered terminal.
  Discovery runs at start, on every Dock click and Dock menu, and when an
  unknown app launches.

## Windows without a jump

The Accessibility API reports a window once it is on screen, so moving it
afterwards always shows. Only a terminal that creates the window at a given
position avoids the jump.

- `OpenWell --spot` prints `x,y` for a new window of the chosen terminal, in
  global coordinates from the top left of the main screen. It takes the size
  of the terminal's frontmost window (800x600 without one). It runs in 60 to
  80 ms after the first call.
- A Dock click records the mouse position for 3 seconds in
  `~/Library/Caches/ch.oetiker.OpenWell/dock-click.json`; `--spot` reads and
  removes it, so it can tell a Dock click from Cmd+N.
- WezTerm binds Cmd+N in `~/.wezterm.lua` to a callback that runs
  `OpenWell --spot` and calls `wezterm.mux.spawn_window` with that position.
  Because Cmd+N is rebound, WezTerm's menu item no longer shows Cmd+N, and a
  Dock click sends the keystroke, which runs the same callback.
- OpenWell leaves a new window alone when it overlaps no window, or when it
  already sits on the spot OpenWell would choose.
- Still jumping: the first window when a Dock click launches the terminal, and
  every window of a terminal without such a binding (iTerm, Terminal).
- `wezterm start --position` is no use: it starts a second WezTerm process.

## Opening a new window

1. Not running: launch the terminal; its first window is placed like any other
   new window.
2. Running: press the menu item of the terminal whose shortcut is Cmd+N, through
   `AXPress`, searching submenus up to three levels (Terminal keeps "New
   Window" in a submenu of Shell). The terminal does not need to be frontmost.
3. No such menu item: send Cmd+N straight to the terminal process with
   `CGEvent.postToPid`. The keystroke never goes through the global event
   stream, so it cannot reach another app while activation is still in progress.

OpenWell runs no command from its configuration. A child process inherits
OpenWell's Accessibility permission, and the config file is writable by every
process of the user, so a configurable command would let any of them use that
permission without a prompt.

## Which windows are placed

OpenWell places a new standard window (`AXStandardWindow`) of a managed app
only when it expects one:

- the window that follows a Dock click or the Dock menu,
- the first window after the app launches,
- a window that appears while the app is frontmost (Cmd+N in the terminal).

Every other window stays where the app put it: windows restored after a
relaunch, windows of a background app. OpenWell does not watch the keyboard,
so it needs no Input Monitoring permission; "frontmost when the window
appeared" stands in for "created by Cmd+N".

## Finding a free spot

- **Screen:** a Dock click uses the screen under the mouse pointer. A window
  created by Cmd+N in a terminal uses the screen of the window that was focused
  before it. The usable area is the screen's `visibleFrame` (without menu bar
  and Dock).
- **Window size:** the size the new window has. If it is larger than the usable
  area, it is shrunk to fit.
- **Obstacles:** on-screen windows of the current Space, layer 0, without the
  new window itself. The new window's `CGWindowID` comes from
  `_AXUIElementGetWindow`, as in FocusWell
  (`Sources/FocusWellCore/PrivateAPI.swift`); terminal windows usually share
  one size, so matching by frame would exclude the wrong window. Each obstacle
  is enlarged by the configured gap.
- **Tiered search:**
  1. A spot that overlaps no window.
  2. If there is none, a spot that overlaps no window of a managed terminal.
     Windows of other apps may be covered.
  3. If there is none, the spot with the least overlap with all windows.
- **Candidates:** with `w`, `h` the window size and `obs` each enlarged
  obstacle, the x positions are
  `{area.minX, area.maxX − w, obs.maxX, obs.minX − w}` and the y positions
  `{area.minY, area.maxY − h, obs.maxY, obs.minY − h}`. Every combination is a
  candidate, plus the anchor position moved into the area (without it,
  `center` on an empty screen ends in a corner); candidates whose rectangle
  leaves the area are dropped. Among equal candidates the one whose origin is
  closest to the anchor in a straight line wins, so next to a wide window the
  new one goes below rather than beside it.
- **Anchor:** `top-left` (default), `top-right`, `center` or `mouse`. For a
  Dock click or the Dock menu, `mouse` counts as `top-left`, because the
  pointer is on the Dock at that moment.

The tiers exist because the window list also contains fully covered windows: a
single maximized browser would otherwise leave no free spot and every placement
would fall back to least overlap.

## Configuration

`~/Library/Application Support/OpenWell/config.json`, created with defaults on first start and
reloaded when it changes. It holds data only.

```json
{
  "terminal": "com.github.wez.wezterm",
  "manage": ["com.github.wez.wezterm", "com.googlecode.iterm2", "…"],
  "gap": 10,
  "anchor": "top-left"
}
```

- `terminal`: bundle ID of the terminal a Dock click opens; the Dock menu sets it.
- `manage`: bundle IDs whose new windows OpenWell places, in addition to the
  discovered terminals. The default is the known list.
- `gap`: distance in points between windows.
- `anchor`: preferred corner, `top-left`, `top-right`, `center` or `mouse`.

## Permissions

OpenWell needs Accessibility only and asks for it on first start. When the
permission is missing or no longer valid, it opens the matching System
Settings page and says what to do. Screen Recording is not needed: OpenWell
reads only window position and size from the window list.

## Structure

- Swift package, macOS 13 or later, no third-party dependencies.
- `OpenWellCore`: the free-spot search as a pure function, with tests.
- `OpenWell`: the app (`main.swift` with the `--spot` mode, `Launcher`,
  `WindowPlacer`, `Spot`, `Terminals`, `Config`). Log messages go to
  `os.Logger` (subsystem `ch.oetiker.OpenWell`) as public text.
- A script builds `OpenWell.app` with `Info.plist` and an icon drawn by a
  script.
- `Makefile` with `build`, `test`, `app` and `install`.

## Distribution

Distribution follows FocusWell.

- Repository: `github.com/moetiker/OpenWell`, public (a private repository of
  a free account gets no branch protection, which the repo-infra release flow
  needs).
- The repository is its own tap: `Casks/openwell.rb`, listed in
  `release_files` of `.github/repo-infra.json`, so the release flow rewrites
  it. Install: `brew install --cask moetiker/openwell/openwell`.
- The app is signed with a Developer ID, notarized and stapled
  (`xcrun stapler staple`). Ad-hoc signing ties the Accessibility permission to
  the hash of one build, so every update would silently lose it.
- CI secrets as in FocusWell: `MACOS_CERTIFICATE_P12`,
  `MACOS_CERTIFICATE_PASSWORD`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`,
  `NOTARY_API_P8`.
- Each release attaches a zipped, signed `OpenWell.app` (`OpenWell-*.zip`) to
  the GitHub release.
- `.github/repo-infra.json` carries the same exceptions as FocusWell: a cask
  instead of a formula, and no Linux packages.

## Order of work

1. Done: free-spot search in `OpenWellCore`, with tests.
2. Done: app, watching and placing, opening new windows.
3. Done: app bundle, icon, Makefile.
4. Done: the old WezTerm setup (`freespot`, `WezTerm New.app`, the `wz_place`
   hook) is retired; `~/.wezterm.lua.bak-openwell` keeps the old file.
5. Done: local test with WezTerm; `--spot` binding, terminal choice and
   discovery added from it.
6. Repository, repo-infra onboarding after FocusWell, README, signing and
   notarization in CI, cask.
7. First release after approval.

## Open questions

- Not yet tested in detail: iTerm's window restoration, and what a posted
  Cmd+N does in a terminal with no open window.
- The README has to show the WezTerm binding for `~/.wezterm.lua`.
