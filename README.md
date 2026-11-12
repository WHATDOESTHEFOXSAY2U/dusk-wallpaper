<p align="center"><img src="docs/icon.png" width="96" alt=""></p>
<h1 align="center">Dusk Wallpaper</h1>
<p align="center">A live calendar wallpaper for the Mac.</p>

<p align="center"><img src="docs/hero.jpg" alt="A soft peach, pink and violet gradient with a large date numeral lower left and a line of the month's days along the bottom"></p>

<br>

<h3 align="center">The date, quietly.</h3>
<p align="center">Today, the week, and every day of the month. Low in the corner, out of the way.</p>

<br>

<h3 align="center">Colour that flows.</h3>
<p align="center">One gradient drifts into the next, all day.</p>
<p align="center"><img src="docs/flow-day.webp" width="640" alt="The wallpaper flowing from Dusk through Meadow, Ember, Ocean and Dawn"></p>
<p align="center"><sub>Sped up here. You set the pace, from 10 seconds to 5 minutes a gradient.</sub></p>

<br>

<h3 align="center">Dark after dark.</h3>
<p align="center">It follows your Mac's appearance. On Auto, it turns at sunset.</p>
<p align="center"><img src="docs/flow-night.webp" width="640" alt="The Night gradient with its hues slowly swinging"></p>

<br>

<h3 align="center">Six gradients. Or your own.</h3>
<p align="center">
  <img src="docs/dusk.jpg" width="32%" alt="Dusk">
  <img src="docs/meadow.jpg" width="32%" alt="Meadow">
  <img src="docs/ember.jpg" width="32%" alt="Ember">
</p>
<p align="center">
  <img src="docs/ocean.jpg" width="32%" alt="Ocean">
  <img src="docs/dawn.jpg" width="32%" alt="Dawn">
  <img src="docs/night.jpg" width="32%" alt="Night">
</p>
<p align="center"><sub>Dusk · Meadow · Ember · Ocean · Dawn · Night</sub></p>

<br>

<h3 align="center">Nearly weightless.</h3>
<p align="center">One Swift file. Around 30 MB of memory. Nothing running when nothing moves.</p>

<br>

## Install

**[Download Dusk Wallpaper](https://github.com/WHATDOESTHEFOXSAY2U/dusk-wallpaper/releases/latest/download/Dusk-Wallpaper.dmg)**, open it, and drag the app onto Applications.

Needs Apple silicon and macOS 14 or later. The app is not notarised by Apple, so the first time you open it, allow it under System Settings › Privacy & Security.

<details>
<summary>Or build it yourself</summary>
<br>

```bash
git clone https://github.com/WHATDOESTHEFOXSAY2U/dusk-wallpaper.git
cd dusk-wallpaper/app
./build.sh
```

Needs Apple's command-line tools (`xcode-select --install`).

</details>

## Use

Click the sun in the menu bar. Pick a gradient, or let it flow.

It starts with your Mac and stays on when you quit the app. *Turn Off Wallpaper*, in the same menu, stops it.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/settings-dark.png">
    <img src="docs/settings-light.png" width="400" alt="The settings window: gradient swatches, your own colours, the flow and its pace, what to show, start at login, and Turn Off Wallpaper">
  </picture>
</p>

## Remove

Untick *Start at login*, choose *Turn Off Wallpaper*, and move the app to the Trash.

<details>
<summary>More</summary>
<br>

**How it stays light.** The gradient is a small picture that Core Animation stretches and the graphics chip blends. The type is two small masks. No web view, no helper processes. Flowing takes a few percent of one core. At rest, or with the desktop covered, it takes none.

**A still for your phone.**

```bash
"/Applications/Dusk Wallpaper.app/Contents/MacOS/DuskWallpaper" --render ~/Desktop/phone.png --palette night --size 393x852 --scale 3 --no-text
```

Every option is listed at the top of `app/main.swift`.

**Make the installer yourself.** `./build.sh --dmg Dusk-Wallpaper.dmg`

**Clear the settings.** `defaults delete local.dusk.wallpaper`

</details>
