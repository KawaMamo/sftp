# Hardened SFTP Server Setup

This repository contains a lightweight, hardened, production-ready SFTP server configuration built on Debian/Ubuntu. The setup enforces **SSH Public Key Authentication** (passwords disabled), strict OpenSSH `chroot` directory isolation, and the exact same hardened daemon security rules for both Docker and native Ubuntu virtual machine deployments.

## 🏗 Architecture & Overview

The server is built around three core security constraints:
1. **System Isolation**: Runs under a restricted system account (`sftpuser`) with shell access disabled (`/usr/sbin/nologin`).
2. **Chroot Jail**: Forces users into `/home/sftpuser` with root ownership (`755`), landing them automatically in `/upload` (`700`).
3. **Key-Only Auth**: Disables password logins entirely (`PasswordAuthentication no`) in favor of Ed25519/RSA public keys.

---

## 🔑 Step 1: Generate Client SSH Keys

Generate an SSH key pair on your client machine or BridgeLink server:

```bash
ssh-keygen -t ed25519 -f sftp_key -N ""
```

This creates two files:
* **`sftp_key`**: The private key (kept secret on your client/BridgeLink).
* **`sftp_key.pub`**: The public key (installed on the SFTP server).

---

## 🐳 Step 2: Deploy Using Docker

### 1. The Dockerfile
Your container uses this hardened build configuration:
```dockerfile
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

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

RUN mkdir -p /home/sftpuser/upload && \
    chown root:root /home/sftpuser && \
    chmod 755 /home/sftpuser && \
    chown sftpuser:sftp_group /home/sftpuser/upload && \
    chmod 700 /home/sftpuser/upload

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

RUN mkdir -p /run/sshd && \
    chmod 755 /run/sshd

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

### 2. Build & Run
```bash
docker build -t sftp-hardened .
docker run -d --name sftp_container -p 2222:22 sftp-hardened
```

### 3. Provision Public Key in Container
```bash
docker exec -it sftp_container mkdir -p /home/sftpuser/.ssh
docker exec -it sftp_container sh -c "echo 'YOUR_PUBLIC_KEY_STRING' > /home/sftpuser/.ssh/authorized_keys"
docker exec -it sftp_container chown -R sftpuser:sftp_group /home/sftpuser/.ssh
docker exec -it sftp_container chmod 700 /home/sftpuser/.ssh
docker exec -it sftp_container chmod 600 /home/sftpuser/.ssh/authorized_keys
```

---

## 🐧 Step 3: Deploy Natively on Ubuntu VM (Exact Docker Parity)

To achieve the exact same configuration natively on an Ubuntu virtual machine, execute the following script with `sudo`:

```bash
#!/bin/bash
set -eu

# 1. Install OpenSSH Server
apt-get update && apt-get install -y --no-install-recommends openssh-server

# 2. Create System Group and User matching Dockerfile
groupadd --system sftp_group
useradd --system \
    --gid sftp_group \
    --home-dir /home/sftpuser \
    --shell /usr/sbin/nologin \
    --no-create-home \
    sftpuser

# 3. Create Chroot Structure & SSH Folder with strict permissions
mkdir -p /home/sftpuser/upload /home/sftpuser/.ssh
chown root:root /home/sftpuser
chmod 755 /home/sftpuser
chown sftpuser:sftp_group /home/sftpuser/upload
chmod 700 /home/sftpuser/upload

chown -R sftpuser:sftp_group /home/sftpuser/.ssh
chmod 700 /home/sftpuser/.ssh

# 4. Insert Client Public Key (Replace with your actual public key string)
echo "YOUR_PUBLIC_KEY_STRING" > /home/sftpuser/.ssh/authorized_keys
chmod 600 /home/sftpuser/.ssh/authorized_keys
chown sftpuser:sftp_group /home/sftpuser/.ssh/authorized_keys

# 5. Apply Exact Dockerfile sshd_config Rules
printf '%s\n' \
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

# 6. Validate configuration and restart SSH service
sshd -t
systemctl restart ssh
```

---

## 🔗 Step 4: BridgeLink (Mirth Connect) Setup

1. **Connector Type**: File Reader (`SFTP`).
2. **Connection Parameters**:
   * **Host**: `localhost` (Docker port `2222`, VM port `22`)
   * **Port**: `2222` (Docker) or `22` (VM)
   * **Directory**: `/upload/` (automatically lands here via `ForceCommand`)
   * **File Filter**: `*.csv`
3. **Authentication**:
   * **Username**: `sftpuser`
   * **Authentication Type**: `Key / Public Key`
   * **Private Key File**: Path to your `sftp_key` file.