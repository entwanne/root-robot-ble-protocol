#!/usr/bin/env bash

###############################################################################
# Title       : robot-driver.sh
# Description : This script sends commands to the 'bluetoothctl' utility. It
#               scans for a Root Robot by a BLE Service UUID, connects, and
#               sends pre-defined motor commands based on arrow key presses.
# Author      : Michael Mogenson
# Email       : mike@codewithroot.com
# Copyright   : 2018 Root Robotics All Rights Reserved
###############################################################################

###############################################################################
#       ┏━━━┓       Usage Instructions:
#       ┃ ▲ ┃       1. Copy this file to a Raspberry Pi running Raspian Stretch
#       ┗━━━┛       2. Turn on Root Robot
# ┏━━━┓ ┏━━━┓ ┏━━━┓ 3. Run this script from command line with bash:
# ┃ ◄ ┃ ┃ ▼ ┃ ┃ ► ┃     pi@raspberrypi:~ $ bash robot-driver.sh
# ┗━━━┛ ┗━━━┛ ┗━━━┛ 4. Use keyboard arrow keys to drive, CTRL-C to exit
###############################################################################

###############################################################################
# Global constants (readonly)
###############################################################################

# regex match for a hexadecimal number like: 0A or 9F
declare -r HEX="[0-9A-F]{2}"

# regex match for a MAC address like: Device AB:CD:EF:12:34:56
declare -r MAC_REGEX="Device ($HEX:$HEX:$HEX:$HEX:$HEX:$HEX)"

# UUID for the Root Robot identifier service
declare -r ROOT_SERVICE_UUID="48c5d828-ac2a-442d-97a3-0c9822b04979"

# UUID for the TX characteristic
declare -r TX_CHAR_UUID="6e400002-b5a3-f393-e0a9-e50e24dcca9e"

###############################################################################
# Motor commands (Incremental ID set to zero, Checksum pre-calculated)
###############################################################################

# device 1, command 4, left motor speed 100, right motor speed 100
declare -r forward_cmd="0x01 0x04 0x00 0x00 0x00 0x00 0x64 0x00 0x00 0x00 0x64"`
`" 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0xD1"

# device 1, command 4, left motor speed -100, right motor speed -100
declare -r back_cmd="0x01 0x04 0x00 0xFF 0xFF 0xFF 0x9C 0xFF 0xFF 0xFF 0x9C"`
`" 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x71"

# device 1, command 4, left motor speed 0, right motor speed 100
declare -r left_cmd="0x01 0x04 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x64"`
`" 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x8A"

# device 1, command 4, left motor speed 100, right motor speed 0
declare -r right_cmd="0x01 0x04 0x00 0x00 0x00 0x00 0x64 0x00 0x00 0x00 0x00"`
`" 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x25"

# device 1, command 4, left motor speed 0, right motor speed 0
declare -r stop_cmd="0x01 0x04 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00"`
`" 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x7E"

###############################################################################
# Global variables
###############################################################################

declare -a output=""    # empty array to hold output of bluetoothctl
declare mac_address=""  # empty string to hold MAC address of robot

###############################################################################
# Helper functions
###############################################################################

function ble_read {
    # read the output of bluetoothctl, save it to the output array, and print it
    local IFS=$'\n'     # split output array by newline
    unset -v output     # clear output array
    read -r -t 1 -d '' -a output -u "${COPROC[0]}"  # read until timeout
    $1 && echo "${output[*]}"   # print contents of output if argument 1 is true
}

function ble_write {
    # write argument 1 to the input of bluetoothctl
    echo "$1" >& "${COPROC[1]}"
}

function disconnect {
    ble_read false  # drain output of bluetoothctl but don't print
    # if the mac address has been set, send the disconnect command
    if [[ -n $mac_address ]]; then
        ble_write "disconnect $mac_address"
        ble_read true
        ble_write "remove $mac_address"
        ble_read true
    fi
    ble_write "exit"  # tell bluetoothctl to exit
}
trap disconnect EXIT # call disconnect whenever the script is exited

###############################################################################
# Start of script
###############################################################################

# start bluetoothctl in background, stdout is COPROC[0], stdin is COPROC[1]
coproc bluetoothctl
ble_read true

# set filter to only show devices with Root Robot UUID
ble_write "set-scan-filter-uuids $ROOT_SERVICE_UUID"
ble_read true

printf "\nSearching for robot\n\n"

# start scanning for devices
ble_write "scan on"

# scan until we find a robot and save the MAC address
while true; do
    ble_read true                           # read from bluetoothctl
    for line in "${output[@]}"; do          # go through output line by line
        if [[ $line =~ $MAC_REGEX ]]; then  # and look for device MAC address
            mac_address=${BASH_REMATCH[1]}  # copy regex match into variable
            break 2                         # break out of both loops
        fi
    done
done

# stop scanning
ble_write "scan off"
ble_read true

printf "\nFound robot, connecting\n\n"

# connect to the found MAC address
ble_write "connect $mac_address"

# search bluetoothctl output for TX characteristic UUID and select it
while true; do
    ble_read true                               # read from bluetoothctl
    for line in "${output[@]}"; do              # go through output line by line
        if [[ $line = *$TX_CHAR_UUID ]]; then   # and look for TX char UUID
            # path to TX characteristic is on previous line, remove space first
            ble_write "select-attribute ${previous_line#[[:space:]]}"
            ble_read true                       # print output
            break 2                             # break out of both loops
        fi
        previous_line=$line
    done
done

printf "\nPress arrow keys to drive robot, press any other key to stop\n"
printf "Use CTRL-C to exit\n\n"

# read the keyboard arrow keys and send motor commands to robot
while read -s -r -n 1 key; do   # read one character
    case $key in                # test the character
        $'\033')                # is character an escape code? (for arrow keys)
            read -s -r -n 2 key # then read two more characters
            case $key in        # see if the two characters are an arrow key
                "[A")
                    printf "UP ARROW:\tDRIVE FORWARDS\n"
                    ble_write "write $forward_cmd"
                    ;;
                "[B")
                    printf "DOWN ARROW:\tDRIVE BACKWARDS\n"
                    ble_write "write $back_cmd"
                    ;;
                "[C")
                    printf "RIGHT ARROW:\tTURN RIGHT\n"
                    ble_write "write $right_cmd"
                    ;;
                "[D")
                    printf "LEFT ARROW:\tTURN LEFT\n"
                    ble_write "write $left_cmd"
                    ;;
            esac
            ;;
        *)                      # if the character is anything else, stop robot
            printf "NO ARROW:\tSTOP\n"
            ble_write "write $stop_cmd"
            ;;
    esac
done
