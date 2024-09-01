# Imaging Instructions

Instructions for imaging the OrangePi 5b for HomeBot

## Flashing Debian 12 image onto OrangePi 5b

1. With no power connected to the OrangePi, connect OrangePi to be imaged to imaging system via USB-C into the Type-C port.
   TODO: Add Image
2. Press and hold the Maskrom button on the OrangePi as you connect power to the OrangePi.
   TODO: Add Images
3. On the imaging system:
   ``` bash
   cd ~/Imager
   ./flash-orangepi.sh
   ```
4. After several minutes the OrangePi should flash and can be disconnected

## Installing HomeAssistant on the OrangePi

1. Boot OrangePi connected to a display, keyboard, and mouse
2. Connect OrangePi to WiFi
3. Open terminal with Ctrl+Alt+T
4. Run:
   ``` bash
   git clone https://github.com/HomeBot-Automation/scripts.git
   cd scripts
   ./ha-setup.sh
   ```
