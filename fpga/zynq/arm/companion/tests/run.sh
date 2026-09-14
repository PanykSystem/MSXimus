#!/bin/bash
# run.sh — prueba en el PC del parser de mandos (hid_pad.c) con el gcc de WSL:
#   wsl -d Ubuntu-24.04 -- bash /mnt/c/.../fpga/zynq/arm/companion/tests/run.sh
# (desde Git Bash el /mnt/... se mangla: lanzarlo desde PowerShell o cmd)
cd "$(dirname "$0")"
gcc -Wall -Wextra -I.. test_hid_pad.c ../hid_pad.c -o /tmp/test_hid_pad && /tmp/test_hid_pad
