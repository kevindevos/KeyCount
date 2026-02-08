<p align="center">
  <img width="128" src="InputCounter/Assets.xcassets/icon_512x512@2x.png">
</p>

<h1 align="center">Input Counter</h1>

<p align="center">
  An open source macOS menu bar application that tracks and displays keystroke and mouse click count only.

  - It does not know which keys are pressed. 
  - No data is collected or transmitted through the network. 
  - The code is open source and can be reviewed by anyone for transparency.

  This app provides activity metrics for informational purposes only. It is not a medical device and should not be used for medical diagnosis or treatment. Always consult with a qualified healthcare professional for any medical concerns.
</p>

<p align="center">
  <img src="https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExaHFsaDJyZHZ6dmtxMnI3MG1qc2M4bXZpOTBrZGl1c3ljMmhnaWYzOSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/WB1Y5VlmofpfQwjpZt/source.gif">
</p>

## Key features
1. Count daily keystrokes and mouse clicks and display them in the macOS menu bar.
2. Saves historical keystroke and mouse click data locally in JSON format in the app's container.
3. Provides a interactive calendar view showing input counts for previous dates. 
4. Export to JSON.

## To run the app:
1. Download the [latest release](https://github.com/kevindevos/KeyCount/releases#latest)
2. Run the app and grant permissions (see below)

## Granting permissions
This application requires your permission to receive events from macOS in order to count and display your keystrokes in the menu bar.

On newer versions of macOS (10.15+) there is an Input Monitoring menu under Security & Privacy within the System Preferences app, and InputCounter will appear there automatically the first time you run it. Simply unlock this menu and check the box next to InputCounter to enable it.

### Other
Icon by Javier Aroche/ [via CC Liscence](https://creativecommons.org/licenses/by/4.0/)

### Original Creator Marcus Del Vecchio
This project is a heavily modified version of the original software created by Marcus Del Vecchio. This project is forked from https://github.com/MarcusDelvecchio/KeyCount. 