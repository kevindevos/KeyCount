<h1 align="center">Input Counter</h1>

<p align="center">
  <img width="128" src="InputCounter/Assets.xcassets/Input Counter.png">
</p>

<p align="center">
  An open source macOS menu bar application that tracks and displays keystroke and mouse click counts only.

  - It does not record which keys are pressed. 
  - No data is collected or transmitted through the network.
  - Counts and history are kept locally only.
  - The code is open source and can be reviewed by anyone for transparency.

  This app provides activity metrics for informational purposes only. It is not a medical device and should not be used for medical diagnosis or treatment. Always consult with a qualified healthcare professional for any medical concerns.
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
Icon by Javier Aroche/ [via CC License](https://creativecommons.org/licenses/by/4.0/)

### Original Creator Marcus Del Vecchio
This project is a heavily modified version of the original software created by Marcus Del Vecchio. This project is forked from https://github.com/MarcusDelvecchio/KeyCount, adding support to track mouse clicks, provides a history and is blocked from using the network.