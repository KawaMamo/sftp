# Hardened SFTP Server Setup

This repository contains a lightweight, hardened, production-ready SFTP server configuration built on Debian. The configuration enforces **SSH Public Key Authentication** (password login is completely disabled), strict OpenSSH `chroot` directory isolation, a dedicated startup script (`docker-entrypoint.sh`), and hardened daemon rules designed for automated ingestion pipelines (such as BridgeLink / Mirth Connect).

---

## 📁 Repository Structure & Explanations

### 1. `Dockerfile` (Build-Time Setup)

```dockerfile
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install OpenSSH server & create isolated system user
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

# Set up secure chroot folder hierarchy
RUN mkdir -p /home/sftpuser/upload && \
    chown root:root /home/sftpuser && \
    chmod 755 /home/sftpuser && \
    chown sftpuser:sftp_group /home/sftpuser/upload && \
    chmod 700 /home/sftpuser/upload

# Apply hardened OpenSSH configuration rules
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

# Set up runtime directories and entrypoint script
RUN mkdir -p /run/sshd && \
    chmod 755 /run/sshd

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

### 2. `docker-entrypoint.sh` (Runtime Initialization)

```sh
#!/bin/sh
set -eu

# Ensure SSH runtime socket directory exists
mkdir -p /run/sshd
chmod 755 /run/sshd

# Dynamically generate unique host keys on first container start
ssh-keygen -A

# Validate SSH configuration syntax
/usr/sbin/sshd -t

# Execute OpenSSH server in the foreground with logging enabled
exec /usr/sbin/sshd -D -e
```

---

## 🔑 Step 1: Generate Client SSH Keys

Because password authentication is disabled, you must generate an SSH key pair on your client machine (or BridgeLink server).

Run this command in your terminal/command prompt:
```bash
ssh-keygen -t ed25519 -f sftp_key -N ""
```
This generates two files in your current working directory:
* `sftp_key` (The **Private Key** – keep this secure on your client machine).
* `sftp_key.pub` (The **Public Key** – to be registered on the SFTP server).

---

## 🐳 Step 2: Deploy using Docker

### 1. Build the Docker Image
Navigate to the directory containing your `Dockerfile` and `docker-entrypoint.sh`:
```bash
docker build -t sftp-hardened .
```

### 2. Run the Container
Map port `2222` on your host machine to port `22` inside the container:
```bash
docker run -d --name sftp_container -p 2222:22 sftp-hardened
```

### 3. Provision the Public Key inside the Container
Copy the contents of your generated `sftp_key.pub` file and inject it into the container:

```bash
# Create the .ssh folder inside the container
docker exec -it sftp_container mkdir -p /home/sftpuser/.ssh

# Append your public key (replace 'YOUR_PUBLIC_KEY_STRING' with actual contents of sftp_key.pub)
docker exec -it sftp_container sh -c "echo 'YOUR_PUBLIC_KEY_STRING' > /home/sftpuser/.ssh/authorized_keys"

# Set strict permissions required by OpenSSH
docker exec -it sftp_container chown -R sftpuser:sftp_group /home/sftpuser/.ssh
docker exec -it sftp_container chmod 700 /home/sftpuser/.ssh
docker exec -it sftp_container chmod 600 /home/sftpuser/.ssh/authorized_keys
```

### 4. Test SFTP Connection
Verify connectivity using the command line:
```bash
sftp -i sftp_key -P 2222 sftpuser@localhost
```

---

## 🔗 Step 3: Configure BridgeLink (Mirth Connect) File Reader

To ingest CSV files into BridgeLink using this hardened SFTP server:

1. **Create/Edit Channel Source:**
   * Open your Channel, go to the **Source** tab, and set **Connector Type** to **File Reader**.

2. **Configure Host & Scheme:**
   * **Scheme:** `SFTP`
   * **Host:** `localhost` (or server IP address)
   * **Port:** `2222`
   * **Directory:** `/upload/` *(or `/` due to `ForceCommand -d /upload` auto-redirection)*
   * **File Name Filter / Pattern:** `*.csv`

3. **Configure Key Authentication:**
   * **Username:** `sftpuser`
   * **Authentication Type:** `Key / Public Key` (or `Identity File`)
   * **Key Location / Private Key:** Specify the path to your private key file (`sftp_key` or `.pem`).
   * **Passphrase:** Leave blank if generated without a password.

4. **Validate:**
   * Click **Test Connection**. BridgeLink will authenticate using the private key and poll for CSV files placed in `/home/sftpuser/upload/`.

---

## 🐧 Alternative: Deploy directly on Native Ubuntu VM

To run this identical hardened setup natively on an Ubuntu virtual machine without Docker:

### 1. Install OpenSSH
```bash
sudo apt-get update && sudo apt-get install -y openssh-server
```

### 2. Create System Group, User, and Directories
```bash
sudo groupadd --system sftp_group
sudo useradd --system -g sftp_group -d /home/sftpuser -s /usr/sbin/nologin sftpuser

sudo mkdir -p /home/sftpuser/upload /home/sftpuser/.ssh
sudo chown root:root /home/sftpuser
sudo chmod 755 /home/sftpuser
sudo chown sftpuser:sftp_group /home/sftpuser/upload
sudo chmod 700 /home/sftpuser/upload
```

### 3. Provision Public Key
```bash
echo "YOUR_PUBLIC_KEY_STRING" | sudo tee /home/sftpuser/.ssh/authorized_keys
sudo chown -R sftpuser:sftp_group /home/sftpuser/.ssh
sudo chmod 700 /home/sftpuser/.ssh
sudo chmod 600 /home/sftpuser/.ssh/authorized_keys
```

### 4. Update OpenSSH Rules
Edit `/etc/ssh/sshd_config`:
```bash
sudo nano /etc/ssh/sshd_config
```
Append the following configuration:
```text
PasswordAuthentication no
PubkeyAuthentication yes

Match Group sftp_group
    ChrootDirectory /home/%u
    ForceCommand internal-sftp -d /upload
    AllowTcpForwarding no
    X11Forwarding no
```

### 5. Restart SSH Service
```bash
sudo sshd -t
sudo systemctl restart ssh
```