#!/bin/bash
echo "ERROR: build_once.sh is retired because its fixed /tmp paths and --deep signing are unsafe." >&2
echo "Use package/build_package.sh with SIGNING_MODE=adhoc or SIGNING_MODE=release." >&2
exit 1
