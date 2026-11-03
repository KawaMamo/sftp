# Sichere SFTP-Server-Einrichtung

Dieses Repository enthält eine leichtgewichtige, sichere SFTP-Server-Konfiguration auf Basis von Debian. Die Konfiguration nutzt eine erzwungene `chroot`-Isolierung (Benutzer werden in ihrem Home-Verzeichnis eingesperrt), deaktivierten Terminal-Zugriff für maximale Sicherheit und einen dedizierten Upload-Ordner für automatisierte Ingestion-Pipelines (wie BridgeLink / Mirth Connect).

---

## 📁 Dockerfile Erklärungen (Zeile für Zeile)

```dockerfile
FROM debian:stable-slim

```

Basis-Image: Startet mit dem offiziellen, minimalen Debian stable-slim-Image, um den Container schlank und sicher zu halten.

Dockerfile
# Install OpenSSH server
```
RUN apt-get update && \
    apt-get install -y openssh-server && \
    rm -rf /var/lib/apt/lists/*

```
OpenSSH-Installation: Aktualisiert die Paketlisten, installiert den OpenSSH-Server-Dienst (der SFTP-Übertragungen steuert) und löscht temporäre Paketdateien, um die Container-Größe zu minimieren.

Dockerfile
# Create an sftp group and user (Username: sftpuser, Password: securepassword123)
```
RUN groupadd sftp_group && \
    useradd -g sftp_group -m -s /bin/false sftpuser && \
    echo "sftpuser:securepassword123" | chpasswd

```
Erstellung von Gruppe & Benutzer:

groupadd: Erstellt eine eigene Gruppe sftp_group zur einfachen Rechteverwaltung.

useradd: Erstellt den Benutzer sftpuser, weist ihn der Gruppe zu, legt automatisch ein Home-Verzeichnis an (-m) und setzt die Shell auf /bin/false, damit sich der Benutzer nicht in einem normalen Terminal anmelden kann.

chpasswd: Setzt das Passwort für den Benutzer.

Dockerfile
# Set up secure chroot directory structure for sftpuser home
```
RUN mkdir -p /home/sftpuser/upload && \
    chown root:root /home/sftpuser && \
    chmod 755 /home/sftpuser && \
    chown sftpuser:sftp_group /home/sftpuser/upload && \
    chmod 755 /home/sftpuser/upload

```
Chroot-Berechtigungen:

Das Haupt-Chroot-Verzeichnis (/home/sftpuser) muss zwingend im Besitz von root sein und darf nur von root beschrieben werden (Vorgabe von OpenSSH).

Der innere Ordner upload gehört sftpuser, damit der Benutzer dort Dateien hochladen, lesen und löschen kann.

Dockerfile
# Configure OpenSSH chroot rules for the sftp_group
```
RUN echo "\nMatch Group sftp_group\n    ChrootDirectory /home/%u\n    ForceCommand internal-sftp\n    X11Forwarding no\n    AllowTcpForwarding no" >> /etc/ssh/sshd_config

```

SSH-Sicherheitsregeln: Fügt Regeln am Ende von /etc/ssh/sshd_config für Mitglieder der sftp_group hinzu. Sie werden in ihrem Home-Verzeichnis (/home/%u) eingesperrt, auf reine SFTP-Dateiübertragungen beschränkt und zusätzliche SSH-Funktionen werden deaktiviert.

Dockerfile
# Expose SSH port
EXPOSE 22

# Start SSH server in the foreground
```
CMD ["/usr/sbin/sshd", "-D"]
```
Ausführung: Gibt Port 22 frei und startet den SSH-Dienst im Vordergrund (-D), damit der Docker-Container aktiv bleibt.

🐳 Verwendung mit Docker
1. Docker-Image bauen
Speichere die Dockerfile in einem Ordner, öffne dort das Terminal und führe aus:

Bash
```
docker build -t sftp-server .
```
2. Container starten
Starte den Container und leite den lokalen Port 2222 auf Port 22 im Container um:

Bash
```
docker run -d --name sftp_container -p 2222:22 sftp-server
```
3. Verbinden
Verbinde dich über einen SFTP-Client (z. B. FileZilla oder BridgeLink):

Host: localhost (oder Server-IP)

Port: 2222

Benutzername: sftpuser

Passwort: securepassword123

Zielverzeichnis: /upload/

🐧 Verwendung direkt auf einer Ubuntu Virtuellen Maschine (Ohne Docker)
Falls du den SFTP-Server direkt auf einem Ubuntu-System ausführen möchtest, führe folgende Befehle nacheinander im Terminal aus:

Schritt 1: OpenSSH-Server installieren
```
sudo apt-get update && sudo apt-get install -y openssh-server
```
Schritt 2: Gruppe, Benutzer und Ordnerstruktur anlegen
```
sudo groupadd sftp_group
sudo useradd -g sftp_group -m -s /bin/false sftpuser
echo "sftpuser:securepassword123" | sudo chpasswd

sudo mkdir -p /home/sftpuser/upload
sudo chown root:root /home/sftpuser
sudo chmod 755 /home/sftpuser
sudo chown sftpuser:sftp_group /home/sftpuser/upload
sudo chmod 755 /home/sftpuser/upload

```
Schritt 3: OpenSSH konfigurieren
Öffne die Konfigurationsdatei:

```
sudo nano /etc/ssh/sshd_config
```
Füge ganz unten in der Datei folgende Zeilen ein:

```
Match Group sftp_group
    ChrootDirectory /home/%u
    ForceCommand internal-sftp
    X11Forwarding no
    AllowTcpForwarding no

```
Speichere die Datei (Strg+O, Eingabe, dann Strg+X).

Schritt 4: SSH-Dienst neu starten
```
sudo systemctl restart ssh
```
Der SFTP-Server ist nun direkt auf dem Standard-Port 22 deiner Ubuntu-VM erreichbar.