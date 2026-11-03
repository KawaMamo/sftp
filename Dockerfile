FROM debian:stable-slim

# Install OpenSSH server
RUN apt-get update && \
    apt-get install -y openssh-server && \
    rm -rf /var/lib/apt/lists/*

# Create an sftp group and user (Username: sftpuser, Password: securepassword123)
RUN groupadd sftp_group && \
    useradd -g sftp_group -m -s /bin/false sftpuser && \
    echo "sftpuser:securepassword123" | chpasswd

# Set up secure chroot directory structure for sftpuser home
RUN mkdir -p /home/sftpuser/upload && \
    chown root:root /home/sftpuser && \
    chmod 755 /home/sftpuser && \
    chown sftpuser:sftp_group /home/sftpuser/upload && \
    chmod 755 /home/sftpuser/upload

# Configure OpenSSH chroot rules for the sftp_group
RUN echo "\nMatch Group sftp_group\n    ChrootDirectory /home/%u\n    ForceCommand internal-sftp\n    X11Forwarding no\n    AllowTcpForwarding no" >> /etc/ssh/sshd_config

# Expose SSH port
EXPOSE 22

# Start SSH server in the foreground
CMD ["/usr/sbin/sshd", "-D"]