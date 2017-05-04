#!/bin/bash

exec xautolock -time 5 \
	-locker "i3lock -i ~/Downloads/wall1.png" \
	-notify 30 \
	-notifier "notify-send -u critical -t 1000 'LOCKING SCREEN in 30 seconds...'" \
	-corners -000

