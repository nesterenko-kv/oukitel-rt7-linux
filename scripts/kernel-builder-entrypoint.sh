#!/bin/sh

# Recreate the Android source-tree layout expected by OPPO's relative symlinks.
# These links live in the disposable container filesystem; the source volumes
# remain separate and persistent.

set -eu

/bin/sh /project/scripts/link-kernel-sources.sh

exec "$@"
