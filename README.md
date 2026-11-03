# Gehaertete SFTP-Server-Einrichtung

Dieses Repository enthaelt eine gehärtete, produktionsbereite SFTP-Server-Konfiguration auf Basis von Debian. Die Konfiguration verwendet reine **SSH-Public-Key-Authentifizierung** (Passwort-Anmeldung ist deaktiviert), eine erzwungene `chroot`-Isolierung, ein Skript fuer den Container-Start (`docker-entrypoint.sh`) sowie strikte Sicherheitsregeln.

---

## 🛠️ Dateien im Projekt

1. `Dockerfile`: Baut das gehärtete Container-Image.
2. `docker-entrypoint.sh`: Initialisiert beim Container-Start Laufzeit-Verzeichnisse und SSH-Host-Schluessel.

---

## 📁 Dockerfile Erklärungen (Zeile für Zeile)

```dockerfile
FROM debian:stable-slim
ENV DEBIAN_FRONTEND=noninteractive
```
* **Basis-Image & Umgebung:** Verwendet Debian `stable-slim` und unterdrueckt interaktive Prompts waehrend der Paketinstallation.

```dockerfile
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
```
* **Installation & System-Benutzer:** Installiert OpenSSH ohne unnoetige Zusatzpakete. Erstellt die Gruppe `sftp_group` und den System-Benutzer `sftpuser` ohne Shell-Zugriff (`/usr/sbin/nologin`).

```dockerfile
# Create chroot structure
RUN mkdir -p /home/sftpuser/upload && \
    chown root:root /home/sftpuser && \
    chmod 755 /home/sftpuser && \
    chown sftpuser:sftp_group /home/sftpuser/upload && \
    chmod 700 /home/sftpuser/upload
```
* **Verzeichnis-Berechtigungen:** 
  * `/home/sftpuser`: Gehärtet für OpenSSH-Chroot (Besitzer `root:root`, Rechte `755`).
  * `/home/sftpuser/upload`: Gehört `sftpuser` mit strikten Rechteeinstellungen (`700`), damit nur dieser Benutzer Zugriff hat.

```dockerfile
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
```
* **SSH-Gehärtung:** Ueberschreibt die `sshd_config`. Passwort-Anmeldung wird vollstaendig deaktiviert, Public-Key-Authentifizierung erzwungen, Port-Forwarding unterbunden und `sftpuser` direkt im Unterordner `/upload` eingesperrt.

```dockerfile
# Create directory for runtime SSH configuration
RUN mkdir -p /run/sshd && \
    chmod 755 /run/sshd

# Entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```
* **Laufzeit & Entrypoint:** Erstellt das erforderliche Laufzeitverzeichnis `/run/sshd`, kopiert das Start-Skript und setzt es als `ENTRYPOINT`.

---

## 📜 Skript-Erklaerung: `docker-entrypoint.sh`

```sh
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
```

### Warum benötigen wir dieses Skript?
1. **Laufzeit vs. Build-Zeit:** SSH-Host-Schluessel (`ssh-keygen -A`) duerfen nicht fest im Image eingebaut werden, da sonst jeder Container dieselben privaten Schluessel nutzen wuerde. Das Skript generiert sie dynamisch beim ersten Start des Containers.
2. **Konfigurationsprüfung:** `/usr/sbin/sshd -t` prüft die Syntax der SSH-Konfiguration vor dem Start.
3. **Prozesssteuerung (`exec`):** Ersetzt den Shell-Prozess durch `sshd` (PID 1), sodass Log-Meldungen direkt an `docker logs` gesendet werden.

---

## 🐳 Verwendung mit Docker

### 1. SSH-Schluesselpaar auf dem Client erstellen
Erstelle auf deinem Client-Rechner ein Schluesselpaar:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/sftp_key -N ""
```

### 2. Image bauen
```bash
docker build -t hardened-sftp .
```

### 3. Container starten
```bash
docker run -d --name sftp_container -p 2222:22 hardened-sftp
```

### 4. Öffentlichen Schlüssel im Container hinterlegen
Kopiere deinen öffentlichen Schlüssel (`~/.ssh/sftp_key.pub`) in den Container:
```bash
docker exec -it sftp_container mkdir -p /home/sftpuser/.ssh
docker exec -it sftp_container chmod 700 /home/sftpuser/.ssh

# Öffentlichen Schlüssel in authorized_keys eintragen:
docker exec -it sftp_container sh -c "echo '$(cat ~/.ssh/sftp_key.pub)' > /home/sftpuser/.ssh/authorized_keys"

# Rechte und Besitzer anpassen (Pflicht für OpenSSH):
docker exec -it sftp_container chown -R sftpuser:sftp_group /home/sftpuser/.ssh
docker exec -it sftp_container chmod 600 /home/sftpuser/.ssh/authorized_keys
```

### 5. Verbindung testen
Standard SFTP-Verbindung via Konsole:
```bash
sftp -i ~/.ssh/sftp_key -P 2222 sftpuser@localhost
```

---

## 🐧 Verwendung direkt auf einer Ubuntu Virtuellen Maschine (Ohne Docker)

Falls du dieselbe gehärtete Konfiguration direkt auf einer Ubuntu-VM einrichten moechtest:

### Schritt 1: OpenSSH installieren & Gruppe/Benutzer anlegen
```bash
sudo apt-get update && sudo apt-get install -y openssh-server

sudo groupadd --system sftp_group
sudo useradd --system \
    --gid sftp_group \
    --home-dir /home/sftpuser \
    --shell /usr/sbin/nologin \
    --no-create-home \
    sftpuser
```

### Schritt 2: Verzeichnisse & Rechte einrichten
```bash
sudo mkdir -p /home/sftpuser/upload
sudo chown root:root /home/sftpuser
sudo chmod 755 /home/sftpuser
sudo chown sftpuser:sftp_group /home/sftpuser/upload
sudo chmod 700 /home/sftpuser/upload
```

### Schritt 3: Öffentlichen Schlüssel hinterlegen
```bash
sudo mkdir -p /home/sftpuser/.ssh
sudo chmod 700 /home/sftpuser/.ssh

# Füge deinen öffentlichen Schlüssel ein:
echo "DEIN_PUBLIC_KEY_STRING" | sudo tee /home/sftpuser/.ssh/authorized_keys

sudo chown -R sftpuser:sftp_group /home/sftpuser/.ssh
sudo chmod 600 /home/sftpuser/.ssh/authorized_keys
```

### Schritt 4: OpenSSH konfigurieren
Öffne `/etc/ssh/sshd_config`:
```bash
sudo nano /etc/ssh/sshd_config
```
Ersetze oder ergänze die Konfiguration durch die gehärteten Regeln:
```text
Port 22
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no
PermitTunnel no
PermitTTY no
Subsystem sftp internal-sftp

Match Group sftp_group
    ChrootDirectory /home/%u
    ForceCommand internal-sftp -d /upload
    AllowTcpForwarding no
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
    X11Forwarding no
    PermitTunnel no
    PermitTTY no
```

### Schritt 5: Konfiguration testen & SSH neu starten
```bash
sudo sshd -t
sudo systemctl restart ssh
```