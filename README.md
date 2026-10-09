# InputBar

A menu bar app for switching a monitor between the machines plugged into it,
over DDC/CI on Apple Silicon. The same binary is also a command-line tool.

- Click the display icon in the menu bar and pick a machine (or press 1/2/3 while
  the menu is open). The active one has a checkmark.
- When this Mac locks, the monitor switches to the PC. When it unlocks, nothing
  happens. Both are configurable from the menu.
- It launches at login. Turn that off with **Launch at Login** in the menu.

| Machine           | Input  | Alias      | Command               |
|-------------------|--------|------------|-----------------------|
| Studio (this Mac) | HDMI 2 | `tostudio` | `inputbar to studio`  |
| Mini              | HDMI 1 | `tomini`   | `inputbar to mini`    |
| PC                | DP 1   | `topc`     | `inputbar to pc`      |

## Enable

```sh
~/Projects/InputBar/inputbar.sh install
source ~/.zshrc
```

This builds the app, copies it to `~/Applications/InputBar.app`, links the CLI to
`~/.local/bin/inputbar`, adds the three aliases to `~/.zshrc` between
`# >>> InputBar >>>` markers and starts the app. On first launch it adds itself
as a login item. Re-run it after changing the code.

Building needs the Xcode command line tools (`xcode-select --install`).

## Disable

```sh
~/Projects/InputBar/inputbar.sh uninstall
unalias tostudio tomini topc   # in terminals that are already open
```

This removes the login item, quits the app, and deletes the app, the CLI link and
the alias block. The source folder stays.

## Command line

```
inputbar                       run the menu bar app
inputbar to <machine>          switch to a machine (studio|mini|pc)
inputbar input [name|value]    read or switch the input (hdmi1, hdmi2, dp1, ...)
inputbar get <setting>         read a setting (brightness, volume, 0x10, ...)
inputbar set <setting> <value> change a setting
inputbar list                  external monitors and their inputs
inputbar login on|off          launch the menu bar app at login
```

## Configuration

Machines, their inputs and the monitor to control are in
[`Sources/InputBar/Config.swift`](Sources/InputBar/Config.swift). The monitor is
matched by part of its product name (`G8`); run `inputbar list` to see names.
After editing, run `./inputbar.sh install` again.

The lock and unlock actions are stored in the app's preferences
(`defaults read com.hugolamarche.inputbar`).

## How it works

- `Monitor.swift` finds external displays in the IORegistry and talks DDC/CI to
  them through IOAVService, a private IOKit API (declared in
  `Sources/CIOAVService`). No drivers or extra permissions are needed.
- Input switches are verified by reading the input back. The Odyssey G8 reports
  its input in its own numbering, which is mapped back to standard codes.
  Monitors often stop answering once they show another input, so silence after a
  switch counts as "probably switched".
- Lock and unlock come from the `com.apple.screenIsLocked` / `screenIsUnlocked`
  distributed notifications.

## Troubleshooting

- Log of every switch and its result: `cat ~/Library/Logs/InputBar.log`
- The menu bar icon turns into a warning triangle when the monitor is not found or
  rejects a switch.
- Slow monitors may need a longer reply delay: `DDC_DELAY_MS=100 inputbar input`
