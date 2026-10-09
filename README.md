# HopDDC

Hop your monitor between computers from the macOS menu bar.

HopDDC switches external monitors' inputs over DDC/CI, so screens can be
shared by several machines (a Mac, a second Mac, a PC, ...) without touching the
monitor's buttons. It runs as a menu bar app, can switch automatically when your
Mac locks or unlocks, and the same binary doubles as a command-line tool.

- Pick a machine from the menu bar (or press 1-9 while the menu is open). The
  active one has a checkmark. Every connected monitor gets its own section.
- Optionally switch when this Mac locks or unlocks, for example to your PC when you
  walk away from the Mac, but only if the monitor is showing the Mac at the time.
- Launches at login and stays out of the Dock.
- Pure Swift, no drivers, no extra permissions.

## Requirements

- A Mac with Apple Silicon (M1 or later). Intel Macs are not supported.
- macOS 13 Ventura or later.
- A monitor with DDC/CI enabled (usually an option in the monitor's own menu),
  connected over HDMI, DisplayPort or USB-C. Some docks and adapters do not pass
  DDC/CI through.
- Xcode or the Xcode command line tools to build (`xcode-select --install`).

## Install

```sh
git clone https://github.com/HugoLamarche/HopDDC.git
cd HopDDC
./hopddc.sh install
```

This builds the app, copies it to `~/Applications/HopDDC.app`, links the command
line tool to `~/.local/bin/hopddc` and starts the app. On first launch it adds
itself as a login item and opens Settings. Run the same command again after
pulling changes.

## Setup

Open **Settings…** from the menu bar icon (or press ⌘, while the menu is open).
Each connected monitor has its own tab, and **General** holds launch at login.

In a monitor's tab:

- **Inputs**: the monitor's inputs, with the one it is showing now marked. HopDDC
  checks the ones the monitor reports; many monitors don't report them, so uncheck
  the ones yours doesn't have. Only checked inputs are offered for machines.
- **Machines**: a name and an input for each computer plugged into this monitor.
  If you don't know which input a computer is on, switch to it with the monitor's
  buttons, then press **Use Current** next to it. A monitor with no machines stays
  out of the menu.
- **This Mac**: which machine is the Mac running HopDDC, and what to do when it
  locks or unlocks. Once this Mac is set, locking only switches the monitor if it
  is showing this Mac, so locking while you are working on another computer leaves
  the screen alone.

Monitors are recognized by serial number, so two identical models keep separate
settings. Settings for a monitor that is not connected are kept until you press
**Forget Monitor**. Everything is stored in the app's preferences
(`defaults read com.hugolamarche.hopddc`) and shared with the command line.

## Command line

```
hopddc                       run the menu bar app
hopddc to <machine>          switch every monitor that has this machine
hopddc input [name|value]    read or switch the input (hdmi1, hdmi2, dp1, ...)
hopddc inputs                the inputs the monitor has (* = current)
hopddc caps                  the monitor's raw capabilities string
hopddc get <setting>         read a setting (brightness, volume, 0x10, ...)
hopddc set <setting> <value> change a setting
hopddc list                  external monitors and their inputs
hopddc login on|off          launch the menu bar app at login
```

Add `-m <monitor>` to act on one monitor: a number from `hopddc list`, a serial
number, or part of the name (`hopddc -m 2 inputs`, `hopddc -m g8 to pc`). Without
it, `input`, `inputs`, `get`, `set` and `caps` use the first monitor that has
machines set up.

Shell aliases make switching quick:

```sh
alias topc='hopddc to pc'
alias tomac='hopddc to mac'
```

## Uninstall

```sh
./hopddc.sh uninstall
defaults delete com.hugolamarche.hopddc   # also remove the settings
```

## How it works

- `Sources/HopDDC/Monitor.swift` finds external displays in the IORegistry and
  talks DDC/CI to them through IOAVService, a private IOKit API declared in
  `Sources/CIOAVService`. Because it is private, a future macOS update could
  break it.
- Input switches are verified by reading the input back. Some monitors report
  their input in their own numbering; known cases (such as the Samsung Odyssey G8)
  are mapped back to standard MCCS codes in `Monitor.swift`. Monitors often stop
  answering once they show another input, so silence after a switch counts as
  "probably switched".
- Lock and unlock come from the `com.apple.screenIsLocked` and
  `com.apple.screenIsUnlocked` distributed notifications.

## Troubleshooting

- Every switch and its result is logged to `~/Library/Logs/HopDDC.log`.
- The menu bar icon turns into a warning triangle when the monitor is not found or
  rejects a switch.
- `hopddc list` shows the monitors HopDDC can see. If yours is missing, check that
  DDC/CI is on in the monitor's menu and try a direct cable instead of a dock.
- Slow monitors may need a longer reply delay: `DDC_DELAY_MS=100 hopddc input`.
- If the checkmark shows the wrong input, your monitor may report inputs in its own
  numbering. Run `hopddc get input` on each input, plus `hopddc caps`, and open an
  issue with the values.

## License

[MIT](LICENSE)
