#!/bin/bash

#
# Initialization
#

# Check if `gum` is installed, add it
if ! pacman -Qs gum > /dev/null 2>&1; then
    echo "📦 Installing the pkg gum..."
    pacman -Sy --noconfirm gum > /dev/null 2>&1
    echo "✅ Successfully installed gum!"
fi

#
# Partition Disk
#
