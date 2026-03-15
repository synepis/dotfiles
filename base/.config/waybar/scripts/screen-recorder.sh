#!/bin/bash

SAVE_DIR=$2
mkdir -p "$SAVE_DIR"

filename="screen_recording_"
filename+=$(date +%F_%H-%M-%S) 
filename+=".mp4"

case $1 in
	status)
		if pgrep -x "wf-recorder" > /dev/null; then
			echo "{\"text\":\"🔴 REC\", \"tooltip\":\"Recording screen\", \"class\":\"recording\"}"
		else
			# Hide if no active recording
			echo "{\"text\":\"\", \"tooltip\":\"Not recording screen\", \"class\":\"stopped\"}"
		fi
		;;
	toggle)
		# Toggle logic: Stop if running, Start if not
        if pgrep -x "wf-recorder" > /dev/null; then
            killall -s SIGINT wf-recorder
        else
            FILENAME="$SAVE_DIR/$filename"
            (wf-recorder -g "$(slurp)" -f "$FILENAME" &)
        fi
		;;
	*)
		echo "Usage: $0 {status|toggle}"
		exit 1
		;;
esac
