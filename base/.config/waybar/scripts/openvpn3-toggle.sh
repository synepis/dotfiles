#!/bin/bash
SESSIONS=$(openvpn3 sessions-list)

STATUS=$(echo "$SESSIONS" | grep "Status:" | awk -F'Status: ' '{print $2}')

if [[ $STATUS = "Connection, Client connected" ]]; then
	openvpn3 session-manage --config ~/vpn/openvpn3.ovpn --disconnect
else
	openvpn3 session-start --config ~/vpn/openvpn3.ovpn
fi
