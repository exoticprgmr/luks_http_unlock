# LUKS HTTP Unlock Script

Automatically unlock a LUKS root partition during boot by fetching the key from a local HTTP keyserver.

If network unlock fails → fallback to password.  
If password is not entered → system reboots after timeout.

Simple. Deterministic. No magic.

## What it does

* Waits for network connection during boot
* Downloads encryption key from HTTP keyserver
* Uses the key to unlock LUKS partition
* If keyserver is not reachable, system asks for password
* If password is not entered before timeout, system reboots

## Requirements

* Debian or Ubuntu based system (tested on Debian 13)
* Root access
* curl installed

cryptsetup-initramfs, busybox & dropbear-initramfs are installed automatically by the setup script.

## Parameters and Setup

During setup, the script will ask you to enter:

* **Keyserver URL** – Address of the HTTP server that stores your LUKS key
* **Network wait timeout (NET_TIMEOUT)** – How long the system waits for network connection during boot
* **Reboot timeout (PASS_TIMEOUT)** – If password is not entered after keyserver failure, the system will reboot automatically

You will also be asked to select:

* LUKS encrypted partition from your system
* network interface used for boot-time communication

### Key Enrollment Requirement

To add the downloaded key to your encrypted partition, you must enter your **existing LUKS password** when prompted.

## Run the setup script as root:

```bash
curl -fsSL -o luks_http_unlock.sh https://raw.githubusercontent.com/exoticprgmr/luks_http_unlock/refs/heads/main/luks_http_unlock.sh
chmod +x luks_http_unlock.sh
sudo ./luks_http_unlock.sh
```

You will be asked for:

* Keyserver URL
* Network wait timeout (NET_TIMEOUT)
* Reboot timeout if password is not entered (PASS_TIMEOUT)

After setup, reboot the system to test unlock.

## Keyserver

The keyserver must return only the raw LUKS key file.
