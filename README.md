<p align="center"><img src="docs/icon.png" width="112" alt=""></p>
<h1 align="center">Dusk Wallpaper</h1>
<p align="center">A live calendar wallpaper for the Mac: soft gradients that flow through the day,<br>today's date in the corner, and next to no cost in memory or battery.</p>

![The wallpaper in its Dusk gradient: a large date numeral lower left with the weekday, month and year beside it, and a line of the month's days along the bottom](docs/hero.jpg)

## What you get

- **A calendar that is always behind your windows.** Today's date, weekday, month and year, the week number, the days left in the year, and one line with every day of the month: today marked, days gone by dimmed, weekends a shade quieter. It sits low and to the left, out of the way.
- **Gradients that move.** Leave *Flow Automatically* on and the wallpaper drifts without pause from one gradient to the next, in steps too small to see.
- **Day and night.** It follows the Mac's Light and Dark appearance: light gradients by day, shades of Night after dark. With the Mac's appearance set to Auto, the wallpaper turns at sunset and sunrise, gliding across in five seconds.
- **Colours made for the screen.** Six gradients tuned for the wide-colour (Display P3) screens of recent Macs, plus one made from three colours of your own.
- **Every display, every Space.** One wallpaper per screen, drawn above the system wallpaper and below the desktop icons.

## Gradients

| Dusk | Meadow | Ember |
| :---: | :---: | :---: |
| ![Dusk](docs/dusk.jpg) | ![Meadow](docs/meadow.jpg) | ![Ember](docs/ember.jpg) |
| **Ocean** | **Dawn** | **Night** |
| ![Ocean](docs/ocean.jpg) | ![Dawn](docs/dawn.jpg) | ![Night](docs/night.jpg) |

### Flowing

By day the flow walks round the five light gradients: Dusk, Meadow, Ember, Ocean, Dawn and back to Dusk. Every blend takes the colourful way round the colour wheel (it is worked out in OKLCH), so two gradients meet in colour and not in grey. You choose how long one gradient takes: 10, 20 or 30 seconds, a minute, or five minutes.

![The day flow from Dusk round to Dusk again](docs/flow-day.webp)

After dark it stays with Night and lets the hues swing slowly, towards teal and blue one way and towards wine and amber the other.

![The night flow: Night with its hues swinging](docs/flow-night.webp)

Both loops are sped up, about eight times faster than the default pace.

## Install

You need a Mac with Apple silicon, macOS 14 or later, and Apple's command-line developer tools (`xcode-select --install`).

```bash
git clone https://github.com/WHATDOESTHEFOXSAY2U/dusk-wallpaper.git
cd dusk-wallpaper/app
./build.sh
```

The script compiles the one source file, signs the app for this Mac (an ad-hoc signature, so no developer account is needed), puts **Dusk Wallpaper** into `/Applications` and starts it. Run it again after any change to the source. A compile error leaves the installed app untouched.

## Using it

The app lives in the menu bar as a small sun on the horizon. Its menu covers day-to-day use:

- **Flow Automatically** turns the flow on and off. While it is on, the line under it says where the flow is, such as *Dusk → Meadow*.
- **Dusk** to **Night** and **Own Colours** stop on one gradient.
- **Settings…** opens the window below. So does opening the app again from Applications or Spotlight.
- **Quit** takes the wallpaper away; your ordinary one is still underneath.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/settings-dark.png">
    <img src="docs/settings-light.png" width="460" alt="The settings window: seven round gradient swatches, three colour wells, the flow checkbox with its pace, two Show checkboxes, Open at login and Quit">
  </picture>
</p>

- **Own colours** are three colour wells, for the bottom left, top right and lower right of the picture. The type turns dark or light by itself, whichever reads better on your colours.
- **Show** hides the line of days or the line with the week number.
- **Open at login** starts the wallpaper with the Mac.

Closing the window leaves the wallpaper running. The app shows in the Dock only while this window is open.

## Small by design

- **One file.** `app/main.swift`, under 900 lines, using only AppKit, Core Animation and Core Text. No web view, no helper processes, no dependencies.
- **One small process.** About 20 MB of memory with one display, about 30 MB with two.
- **No work when nothing moves.** Resting on one gradient it uses no CPU at all: no timers, no redraws. The same holds while the desktop is completely covered, by a full-screen app for instance. The flow stops, and picks up with a short glide when the desktop is back in view.
- **Cheap when it does move.** The gradient is a 450-pixel-wide, 16-bit picture that Core Animation stretches and dithers, and the type is two small masks. While flowing, the app draws twelve such pictures per gradient and lets the graphics chip blend between neighbours, so one step is one opacity change. On a 14-inch M1 MacBook Pro with a second display attached this measures about 2% of one core at the default pace and under 4% at the fastest.
- **Nothing to drift.** What is on screen is a pure function of the clock and three saved numbers, so sleep, clock changes and restarts cannot knock it out of step.

## Stills from the command line

The same code writes the wallpaper as a 16-bit Display P3 PNG at any size. The pictures on this page were made this way, and it is a quick route to a matching wallpaper for a phone:

```bash
APP="/Applications/Dusk Wallpaper.app/Contents/MacOS/DuskWallpaper"
"$APP" --render ~/Desktop/ocean.png --palette ocean --size 1800x1169 --scale 2
"$APP" --render ~/Desktop/phone.png --palette night --size 393x852 --scale 3 --no-text
"$APP" --render ~/Desktop/between.png --at 1.5    # half-way from Meadow to Ember
```

All the options are listed at the top of `app/main.swift`.

## Removing it

Untick *Open at login*, quit from the menu and move **Dusk Wallpaper** from Applications to the Trash. To clear its settings as well:

```bash
defaults delete local.dusk.wallpaper
```

## What is in here

```
app/main.swift     the whole app
app/build.sh       builds, signs, installs and restarts it
app/AppIcon.icns   the icon
docs/              the pictures on this page
```
