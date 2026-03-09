#!/bin/bash
directory=$1

[[ "${directory}" != */ ]] && directory+="/"

filename="screenshot_"
filename+=$(date +%F_%H-%M-%S) 
filename+=".png"

filepath=$directory
filepath+=$filename

slurp | grim -g - $filepath

