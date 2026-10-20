#!/bin/sh
# Wird vom pacman-Hook beim Bauen der ISO ausgeführt
sed -i -E 's/^#[[:space:]]*((de_DE|en_US)\.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen
