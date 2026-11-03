
#!/bin/sh
set -eu

# Ensure SSH runtime directory exists
mkdir -p /run/sshd
chmod 755 /run/sshd

# Generate unique host keys if they do not exist
ssh-keygen -A

# Validate SSH configuration
/usr/sbin/sshd -t

# Start SSH server in foreground
exec /usr/sbin/sshd -D -e