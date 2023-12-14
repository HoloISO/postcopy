#!/bin/bash
SCRIPT=$(realpath "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
srcdir=${SCRIPTPATH}/src
mkdir -p ${srcdir}
pkgdir=${SCRIPTPATH}
 ## jupiter-hw-support
    git clone https://gitlab.com/evlaV/jupiter-hw-support/ ${srcdir}/jupiter-hw-support
    rm -rf ${srcdir}/jupiter-hw-support/usr/bin/jupiter-controller-update
    rm -rf ${srcdir}/jupiter-hw-support/usr/bin/jupiter-biosupdate
    rm -rf ${srcdir}/jupiter-hw-support/usr/bin/steamos-priv-write
    rsync -a "$srcdir"/jupiter-hw-support/* "$pkgdir"
    cd $pkgdir/usr/share/steamos/
    xcursorgen $pkgdir/usr/share/steamos/steamos-cursor-config $pkgdir/usr/share/icons/steam/cursors/default
    cd "$pkgdir/usr/share/jupiter_bios_updater"
      # Remove gtk2 binary and respective build/start script - unused
      # Attempts to use gtk2 libraries which are not on the device.
    rm h2offt-g H2OFFTx64-G.sh
      # Driver module -- doesn't currently build, and not supported
    rm -rf driver
    cd $pkgdir
    rm -rf "${pkgdir}/usr/lib/udev/rules.d/99-steamos-automount.rules"
    ##

    ## steamdeck-kde-presets
    git clone https://gitlab.com/evlaV/steamdeck-kde-presets ${srcdir}/steamdeck-kde-presets
    rm -rf "${srcdir}/steamdeck-kde-presets/etc/X11/Xsession.d/50rotate-screen"
    rm -rf "${srcdir}/steamdeck-kde-presets/etc/sddm.conf.d/"
    rm -rf "${srcdir}/steamdeck-kde-presets/usr/bin/jupiter-plasma-bootstrap"
    cp -R ${srcdir}/steamdeck-kde-presets/* "$pkgdir"
    ##
    echo "Cleaning up..."
    rm -rf ${srcdir}/jupiter-hw-support
    rm -rf ${srcdir}/steamdeck-kde-presets