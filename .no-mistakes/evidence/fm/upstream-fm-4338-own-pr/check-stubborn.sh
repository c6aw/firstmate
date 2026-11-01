#!/usr/bin/env bash
printf 'stubborn finding\n'
( trap '' TERM; exec -a fm-lab-marker-stubborn sleep 30 ) &
( trap '' TERM; exec -a fm-lab-marker-stubborn sleep 30 )
