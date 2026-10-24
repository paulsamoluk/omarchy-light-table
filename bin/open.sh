#!/bin/sh
# Light Table — hand a file to the user's default handler.
#
# `gio open` (GLib, same mimeapps associations as xdg-open) returns as soon as
# the handler is launched; the generic `xdg-open` path can sit in the
# foreground for as long as the viewer stays open, which looks like a hang.
# Try gio first, then xdg-open detached, so nothing blocks the widget.
set -u

target=${1:-}
[ -n "$target" ] || exit 1

if command -v gio >/dev/null 2>&1 && gio open "$target" >/dev/null 2>&1; then
  exit 0
fi

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$target" >/dev/null 2>&1 &
  exit 0
fi

exit 1
