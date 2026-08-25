# Initial architecture

The lowest-risk first milestone is not a full mainline tablet port. It is:

1. The stock boot chain starts a compatible custom Linux 4.19.191 kernel.
2. Android early userspace retains responsibility for board-specific hardware
   initialization and `/data` decryption.
3. A Debian ARM64 root filesystem runs from a dedicated filesystem image.
4. The custom kernel supplies the namespaces, cgroups, netfilter, OverlayFS,
   and other features required by Docker Engine.
5. SSH over USB networking provides a recovery-friendly management path.

Display, touch, Wi-Fi/Bluetooth, suspend, GPU acceleration, and cellular modem
support can then be ported independently without blocking the headless server
milestone.
