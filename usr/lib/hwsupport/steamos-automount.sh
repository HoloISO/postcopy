#!/bin/bash

set -euo pipefail

. /usr/lib/hwsupport/common-functions

# Originally from https://serverfault.com/a/767079

# This script is called from our systemd unit file to mount or unmount
# a USB drive.

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
DEVICE="/dev/${DEVBASE}"
DECK_UID=$(id -u deck)
DECK_GID=$(id -g deck)

send_steam_url()
{
  local command="$1"
  local arg="$2"
  local encoded=$(urlencode "$arg")
  if pgrep -x "steam" > /dev/null; then
      # TODO use -ifrunning and check return value - if there was a steam process and it returns -1, the message wasn't sent
      # need to retry until either steam process is gone or -ifrunning returns 0, or timeout i guess
      systemd-run -M ${DECK_UID}@ --user --collect --wait sh -c "./.steam/root/ubuntu12_32/steam steam://${command}/${encoded@Q}"
      echo "Sent URL to steam: steam://${command}/${arg} (steam://${command}/${encoded})"
  else
      echo "Could not send steam URL steam://${command}/${arg} (steam://${command}/${encoded}) -- steam not running"
  fi
}

# From https://gist.github.com/HazCod/da9ec610c3d50ebff7dd5e7cac76de05
urlencode()
{
    [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

do_mount()
{
    declare -i ret
    # NOTE: these values are ABI, since they are sent to the Steam client
    readonly FSCK_ERROR=1
    readonly MOUNT_ERROR=2

    # Get info for this drive: $ID_FS_LABEL, and $ID_FS_TYPE
    dev_json=$(lsblk -o PATH,LABEL,FSTYPE --json -- "$DEVICE" | jq '.blockdevices[0]')
    ID_FS_LABEL=$(jq -r '.label | select(type == "string")' <<< "$dev_json")
    ID_FS_TYPE=$(jq -r '.fstype | select(type == "string")' <<< "$dev_json")

    # Global mount options
    OPTS="noatime"

    # File system type specific mount options
    #if [[ ${ID_FS_TYPE} == "vfat" ]]; then
    #    OPTS+=",users,gid=100,umask=000,shortname=mixed,utf8=1,flush"
    #fi

    # We need symlinks for Steam for now, so only automount ext4 as that'll Steam will format right now
    if [[ ${ID_FS_TYPE} != "ext4" ]]; then
        echo "Error mounting ${DEVICE}: wrong fstype: ${ID_FS_TYPE} - ${dev_json}"
        exit 2
    fi

    # Try to repair the filesystem if it's known to have errors.
    # ret=0 means no errors, 1 means that errors were corrected.
    # In all other cases we try to mount the fs read-only and report an error.
    ret=0
    fsck.ext4 -y "${DEVICE}" || ret=$?
    if (( ret != 0 && ret != 1 )); then
        send_steam_url "system/devicemountresult" "${DEVBASE}/${FSCK_ERROR}"
        echo "Error running fsck on ${DEVICE} (status = $ret)"
        OPTS+=",ro"
    else
        OPTS+=",rw"
    fi

    # Ask udisks to auto-mount. This needs a version of udisks that supports the 'as-user' option.
    mount_point=$(make_dbus_udisks_call call 'data[0]' s         \
                                 "block_devices/${DEVBASE}"      \
                                 Filesystem Mount                \
                                 'a{sv}' 3                       \
                                 as-user s deck                  \
                                 auth.no_user_interaction b true \
                                 options s "$OPTS")

    # Ensure that the deck user can write to the root directory
    if ! setpriv --clear-groups --reuid "${DECK_UID}" --regid "${DECK_GID}" test -w "${mount_point}"; then
        chmod 777 "${mount_point}" || true
    fi

    # Create a symlink from /run/media to keep compatibility with apps
    # that use the older mount point (for SD cards only).
    case "${DEVBASE}" in
        mmcblk0p*)
            if [[ -z "${ID_FS_LABEL}" ]]; then
                old_mount_point="/run/media/${DEVBASE}"
            else
                old_mount_point="/run/media/${mount_point##*/}"
            fi
            if [[ ! -d "${old_mount_point}" ]]; then
                rm -f -- "${old_mount_point}"
                ln -s -- "${mount_point}" "${old_mount_point}"
            fi
            ;;
    esac

    echo "**** Mounted ${DEVICE} at ${mount_point} ****"
}

do_unmount()
{
    local mount_point=$(findmnt -fno TARGET "${DEVICE}" || true)
    if [[ -n $mount_point ]]; then
        # Remove symlink to the mount point that we're unmounting
        find /run/media -maxdepth 1 -xdev -type l -lname "${mount_point}" -exec rm -- {} \;
    else
        # If we don't know the mount point then remove all broken symlinks
        find /run/media -maxdepth 1 -xdev -xtype l -exec rm -- {} \;
    fi
}

case "${ACTION}" in
    add)
        do_mount
        ;;
    remove)
        do_unmount
        ;;
    *)
        usage
        ;;
esac
