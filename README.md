<p align="center">
  <img width="128" src="AntiRSICounter/Assets.xcassets/icon_512x512@2x.png">
</p>

<h1 align="center">KeyCount</h1>

<p align="center">
  An open source macOS menu bar application that tracks and displays keystroke and mouse click count.
</p>

<p align="center">
  <img src="https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExaHFsaDJyZHZ6dmtxMnI3MG1qc2M4bXZpOTBrZGl1c3ljMmhnaWYzOSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/WB1Y5VlmofpfQwjpZt/source.gif">
</p>

## Key features
1. Count daily keystrokes and mouse clicks and display them in the macOS menu bar
2. Saves keystroke and mouse click data to a local file with path `/Users/<USER>/Library/Containers/com.kevindevos.AntiRSICounter/Data/Documents` in json format.

## To run the app:
1. Download the [latest release](https://github.com/kevindevos/KeyCount/releases#latest)
2. Run the app and grant permissions (see below)

## Granting permissions
This application requires your permission to receive events from macOS in order to count and display your keystrokes in the menu bar.

On newer versions of macOS (10.15+) there is an Input Monitoring menu under Security & Privacy within the System Preferences app, and AntiRSICounter will appear there automatically the first time you run it. Simply unlock this menu and check the box next to AntiRSICounter to enable it.

### Other
Icon by Javier Aroche/ [via CC Liscence](https://creativecommons.org/licenses/by/4.0/)

### Original Creator
This project is a modified version of the original software forked from https://github.com/MarcusDelvecchio/KeyCount. New features and adjustments have been made to suit my personal needs.