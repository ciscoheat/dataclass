#!/usr/bin/env bash

# Some xvfb settings
export DISPLAY=:99.0
export AUDIODEV=null

# Download and unzip the flash player
wget http://fpdownload.macromedia.com/pub/flashplayer/updaters/11/flashplayer_11_sa_debug.i386.tar.gz
tar -xf flashplayer_11_sa_debug.i386.tar.gz -C ~

# Create a configuration file so the trace log is enabled
echo -e "ErrorReportingEnable=1\nTraceOutputFileEnable=1" > ~/mm.cfg

# Add the current directory as trusted, so exit() can be used
mkdir -p ~/.macromedia/Flash_Player/#Security/FlashPlayerTrust
echo "`pwd`" > ~/.macromedia/Flash_Player/#Security/FlashPlayerTrust/travis.cfg
