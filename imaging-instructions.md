# Imaging Instructions

Instructions for imaging the OrangePi 5b for HomeBot

## Flashing Debian 12 image onto OrangePi 5b

1. With no power connected to the OrangePi, connect OrangePi to be imaged to imaging system via USB-C into the Type-C port.
   
   ![OrangePi 5b Type-C port](https://raw.githubusercontent.com/HomeBot-Automation/scripts/main/orangepi5b_type-c.png)
3. Press and hold the Maskrom button on the OrangePi as you connect power to the OrangePi.
   
   ![OrangePi 5b Maskrom button](https://raw.githubusercontent.com/HomeBot-Automation/scripts/main/orangepi5b_maskrom.png)
   ![OrangePi 5b Type-C power](https://raw.githubusercontent.com/HomeBot-Automation/scripts/main/orangepi5b_type-c-power.png)
5. On the imaging system:
   ``` bash
   cd ~/Imager
   ./flash-orangepi.sh
   ```
6. After several minutes the OrangePi should flash and can be disconnected

## Installing HomeAssistant on the OrangePi

1. Boot OrangePi connected to a display, keyboard, and mouse
2. Connect OrangePi to WiFi
3. Open terminal with Ctrl+Alt+T
4. Run:
   ``` bash
   git clone --branch homebot-ha https://github.com/HomeBot-Automation/scripts.git
   cd scripts
   ./ha-setup.sh
   ```
When prompted to choose a system, make sure you pick raspberrypi4-64.
