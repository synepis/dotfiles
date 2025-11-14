#!/usr/bin/env bash

SESSIONS=$(openvpn3 sessions-list)

STATUS=$(echo "$SESSIONS" | grep "Status:" | awk -F'Status: ' '{print $2}')
DEVICE=$(echo "$SESSIONS" | grep "Device:" | awk -F'Device: ' '{print $2}')

if [[ $STATUS = "Connection, Client connected" ]]; then
	echo "{\"text\":\"VPN <span foreground='#27cc27'> $DEVICE</span>\"}"
else

	echo "{\"text\":\"VPN <span foreground='#cc2737'></span>\"}"
fi
