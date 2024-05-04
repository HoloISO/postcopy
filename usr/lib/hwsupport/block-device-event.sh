#!/bin/bash

set -euo pipefail

. /usr/lib/hwsupport/common-functions

usage()
{
    echo "Usage: $0 {add|remove} device_name (e.g. sdb1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

ACTION=$1
DEVBASE=$2

# Shared between this and format-device.sh to ensure we're not
# double-triggering nor automounting while formatting or vice-versa.
if ! create_lock_file "$DEVBASE"; then
    exit 0
fi

do_add()
{
    declare -i current_time=$(date +%s)
    declare -i detected_us

    # Prior to talking to udisks, we need all udev hooks (we were started by one) to finish, so we know it has knowledge
    # of the drive.  Our own rule starts us as a service with --no-block, so we can wait for rules to settle here
    # safely.
    if ! udevadm settle; then
        echo "Failed to wait for \`udevadm settle\`" >&2
        exit 1
    fi

    drive=$(make_dbus_udisks_call get-property data o "block_devices/${DEVBASE}" Block Drive)
    detected_us=$(make_dbus_udisks_call get-property data t "${drive}" Drive TimeMediaDetected)
    # The 5 seconds window is taken from the original GNOME fix that inspired this one
    # https://gitlab.gnome.org/GNOME/gvfs/-/commit/b4800b987b4a8423a52306c9aef35b3777464cc5
    if (( detected_us / 1000000 + 5 < current_time )); then
        echo "Skipping mounting /dev/${DEVBASE} because it has not been inserted recently" >&2
        exit 0
    fi

    /usr/lib/hwsupport/steamos-automount.sh add "${DEVBASE}"
}

do_remove()
{
    /usr/lib/hwsupport/steamos-automount.sh remove "${DEVBASE}"
}

case "${ACTION}" in
    add)
        do_add
        ;;
    remove)
        do_remove
        ;;
    *)
        usage
        ;;
esac
