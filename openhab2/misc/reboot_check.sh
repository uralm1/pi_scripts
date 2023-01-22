#!/bin/bash
# add to sudoers file:
# openhab ALL= NOPASSWD: /sbin/shutdown, /usr/bin/touch
sudo touch /forcefsck
sleep 1
sudo shutdown -r --no-wall now
