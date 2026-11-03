# Hardened SFTP Server Setup

This repository contains a lightweight, hardened, production-ready SFTP server configuration built on Debian. The setup enforces **SSH Public Key Authentication** (passwords disabled), strict OpenSSH `chroot` directory isolation, a dedicated runtime entrypoint script (`docker-entrypoint.sh`), and hardened daemon security rules designed for automated ingestion pipelines (such as BridgeLink / Mirth Connect).

---

## 🏗 Architecture & Overview

The server is built around three core components:

1. **`Dockerfile`**: Sets up a minimal Debian container, creates an isolated system user (`sftpuser`), builds the required `chroot` directory structure (`/home/sftpuser/upload`), and locks down the OpenSSH configuration (`sshd_config`).
2. **`docker-entrypoint.sh`**: Handles container startup tasks including runtime directory initialization (`/run/sshd`), dynamic host key generation (`ssh-keygen -A`), configuration syntax validation, and launching `sshd` in the foreground.
3. **SSH Key Authentication**: Password logins are completely disabled (`PasswordAuthentication no`). Clients connect using an ED25519 or RSA private key matched against `/home/sftpuser/.ssh/authorized_keys`.

---

## 🔑 Step 1: Generate Client SSH Keys

Before connecting, generate an SSH key pair on your client machine or BridgeLink server:

```bash
ssh-keygen -t ed25519 -f sftp_key -N ""
```

This creates two files in your current folder:
* **`sftp_key`**: The private key (keep this secret; used by your SFTP client or BridgeLink).
* **`sftp_key.pub`**: The public key (uploaded to the SFTP server).

---

## 🐳 Step 2: Deploy Using Docker

### 1. Build the Docker Image
Navigate to the directory containing your `Dockerfile` and `docker-entrypoint.sh`:
```bash
docker build -t sftp-hardened .
```

### 2. Launch the Container
Map port `2222` on your host to port `22` in the container:
```bash
docker run -d --name sftp_container -p 2222:22 sftp-hardened
```

### 3. Provision the Public Key
Inject your generated `sftp_key.pub` into the container and set the strict ownership and permissions required by OpenSSH:

```bash
# Create the SSH folder inside the container
docker exec -it sftp_container mkdir -p /home/sftpuser/.ssh

# Append your public key (replace YOUR_PUBLIC_KEY_STRING with actual sftp_key.pub contents)
docker exec -it sftp_container sh -c "echo 'YOUR_PUBLIC_KEY_STRING' > /home/sftpuser/.ssh/authorized_keys"

# Enforce strict OpenSSH permissions
docker exec -it sftp_container chown -R sftpuser:sftp_group /home/sftpuser/.ssh
docker exec -it sftp_container chmod 700 /home/sftpuser/.ssh
docker exec -it sftp_container chmod 600 /home/sftpuser/.ssh/authorized_keys
```

### 4. Verify Connection
Test the SFTP connection from your command line:
```bash
sftp -i sftp_key -P 2222 sftpuser@localhost
```

---

## 🔗 Step 3: BridgeLink (Mirth Connect) Setup

To configure BridgeLink to automatically pull CSV files from this SFTP server:

1. **Connector Type**: In your Channel **Source** tab, set **Connector Type** to **File Reader**.
2. **Connection Parameters**:
   * **Scheme**: `SFTP`
   * **Host**: `localhost` (or server IP)
   * **Port**: `2222`
   * **Directory**: `/upload/` *(or `/` due to automatic `ForceCommand -d /upload` redirection)*
   * **File Name Filter / Pattern**: `*.csv`
3. **Authentication Settings**:
   * **Username**: `sftpuser`
   * **Authentication Type**: `Key / Public Key` (or `Identity File`)
   * **Key Location / Private Key**: Specify the path to your private key file (`sftp_key`).
   * **Passphrase**: Leave blank (if generated without one).
4. **Test Connection**: Click **Test Connection** to confirm BridgeLink can authenticate and access the upload folder.

---

## 🐧 Alternative: Deploy Natively on Ubuntu VM

To replicate this hardened setup on a bare-metal or virtual Ubuntu machine without Docker:

### 1. Install OpenSSH
```bash
sudo apt-get update && sudo apt-get install -y openssh-server
```

### 2. Create User, Group, and Directories
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

### 4. Configure `/etc/ssh/sshd_config`
Append the following security rules to `/etc/ssh/sshd_config`:
```text
PasswordAuthentication no
PubkeyAuthentication yes

Match Group sftp_group
    ChrootDirectory /home/%u
    ForceCommand internal-sftp -d /upload
    AllowTcpForwarding no
    X11Forwarding no
```

### 5. Validate & Restart SSH Service
```bash
sudo sshd -t
sudo systemctl restart ssh
```