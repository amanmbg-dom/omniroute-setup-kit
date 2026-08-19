#!/data/data/com.termux/files/usr/bin/env bash
# =============================================================================
#  boot.sh - Termux:Boot entry point. Installed to
#  ~/.termux/boot/omniroute-boot.sh by install-omniroute.sh. Termux:Boot runs
#  every script in ~/.termux/boot/ when the phone boots (after you've opened
#  the Termux:Boot app once and disabled battery optimization for Termux +
#  Termux:Boot in Android settings - install-omniroute.sh does both where it
#  can and prints the one-time manual steps).
#
#  Waits 20s so the network is up, then starts the whole stack detached.
# =============================================================================
sleep 20
exec bash ~/omniroute-android/start-omniroute.sh
