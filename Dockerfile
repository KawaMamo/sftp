
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install OpenSSH server
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system sftp_group && \
    useradd --system \
        --gid sftp_group \
        --home-dir /home/sftpuser \
        --shell /usr/sbin/nologin \
        --no-create-home \
        sftpuser

# Create chroot structure
RUN mkdir -p /home/sftpuser/upload && \
    chown root:root /home/sftpuser && \
    chmod 755 /home/sftpuser && \
    chown sftpuser:sftp_group /home/sftpuser/upload && \
    chmod 700 /home/sftpuser/upload

# Configure SSH
RUN printf '%s\n' \
    'Port 22' \
    'PermitRootLogin no' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' \
    'PubkeyAuthentication yes' \
    'PermitEmptyPasswords no' \
    'MaxAuthTries 3' \
    'LoginGraceTime 30' \
    'X11Forwarding no' \
    'AllowTcpForwarding no' \
    'AllowAgentForwarding no' \
    'AllowStreamLocalForwarding no' \
    'PermitTunnel no' \
    'PermitTTY no' \
    'Subsystem sftp internal-sftp' \
    '' \
    'Match Group sftp_group' \
    '    ChrootDirectory /home/%u' \
    '    ForceCommand internal-sftp -d /upload' \
    '    AllowTcpForwarding no' \
    '    AllowAgentForwarding no' \
    '    AllowStreamLocalForwarding no' \
    '    X11Forwarding no' \
    '    PermitTunnel no' \
    '    PermitTTY no' \
    > /etc/ssh/sshd_config

# Create directory for runtime SSH configuration
RUN mkdir -p /run/sshd && \
    chmod 755 /run/sshd

# Entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]