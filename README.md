# DDCHop

A menu bar app for switching a monitor between the machines plugged into it,
over DDC/CI on Apple Silicon. The same binary is also a command-line tool.

- Click the display icon in the menu bar and pick a machine (or press 1-9 while
  the menu is open). The active one has a checkmark.
- It can switch the monitor when this Mac locks or unlocks, for example to the PC
  when you walk away from the Mac.
- It launches at login. Turn that off in Settings.

## Settings

Open **Settings…** from the menu (or press ⌘, while the menu is open):

- **Monitor**: which external monitor to control, picked from the ones detected.
- **Machines**: a name and an input for each machine plugged into the monitor.
  **Use Current** fills in the input the monitor is showing right now, so you can
  switch to a machine with the monitor's buttons and capture its input.
- **This Mac**: what to do when this Mac locks or unlocks, and launch at login.

On first launch with no machines it opens Settings by itself. Everything is stored
in the app's preferences (`defaults read com.hugolamarche.ddchop`) and shared
with the command line.

## Enable

```sh
~/Projects/DDCHop/ddchop.sh install
source ~/.zshrc
```

This builds the app, copies it to `~/Applications/DDCHop.app`, links the CLI to
`~/.local/bin/ddchop`, adds the `tostudio`, `tomini` and `topc` aliases to
`~/.zshrc` between `# >>> DDCHop >>>` markers (edit `ddchop.sh` to change
them) and starts the app. On first launch it adds itself
as a login item. Re-run it after changing the code.

Building needs the Xcode command line tools (`xcode-select --install`).

## Disable

```sh
~/Projects/DDCHop/ddchop.sh uninstall
unalias tostudio tomini topc   # in terminals that are already open
```

This removes the login item, quits the app, and deletes the app, the CLI link and
the alias block. Settings and the source folder stay; remove the settings with
`defaults delete com.hugolamarche.ddchop`.

## Command line

```
ddchop                       run the menu bar app
ddchop to <machine>          switch to a machine, by its name in Settings
ddchop input [name|value]    read or switch the input (hdmi1, hdmi2, dp1, ...)
ddchop get <setting>         read a setting (brightness, volume, 0x10, ...)
ddchop set <setting> <value> change a setting
ddchop list                  external monitors and their inputs
ddchop login on|off          launch the menu bar app at login
```

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

- Log of every switch and its result: `cat ~/Library/Logs/DDCHop.log`
- The menu bar icon turns into a warning triangle when the monitor is not found or
  rejects a switch.
- Slow monitors may need a longer reply delay: `DDC_DELAY_MS=100 ddchop input`
