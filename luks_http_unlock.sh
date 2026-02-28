#!/bin/bash

set -e

# Must be root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

echo "=== HTTP LUKS Unlock Setup ==="
echo

read -rp "Enter keyserver URL (e.g. http://192.168.1.10/key): " URL
read -rp "Enter maximum time to wait for the network, in seconds (NET_TIMEOUT): " NET_TIMEOUT
read -rp "Enter reboot timout, in seconds (PASS_TIMEOUT): " PASS_TIMEOUT

if [ -z "$URL" ] || [ -z "$NET_TIMEOUT" ] || [ -z "$PASS_TIMEOUT" ]; then
    echo "All parameters are required."
    exit 1
fi

echo "[+] Installing dependencies..."
apt update
apt install -y cryptsetup-initramfs curl busybox dropbear-initramfs

KEY_TMP="/tmp/luks_http_key"

echo "[+] Downloading key from $URL..."
if ! curl -fsS "$URL" -o "$KEY_TMP"; then
    echo "Failed to download key."
    exit 1
fi

if [ ! -s "$KEY_TMP" ]; then
    echo "Downloaded key is empty."
    exit 1
fi

chmod 600 "$KEY_TMP"

echo "[+] Detecting LUKS entries from /etc/crypttab..."

ROOT_CANDIDATES=()

while read -r name device rest; do
    if [ -n "$name" ] && [ -n "$device" ]; then
        ROOT_CANDIDATES+=("$name:$device")
    fi
done < <(grep -v '^#' /etc/crypttab)

if [ "${#ROOT_CANDIDATES[@]}" -eq 0 ]; then
    echo "No LUKS entries found in /etc/crypttab."
    exit 1
fi

echo "Available LUKS entries:"
select entry in "${ROOT_CANDIDATES[@]}"; do
    if [ -n "$entry" ]; then
        LUKS_NAME="${entry%%:*}"
        LUKS_PART="${entry##*:}"
        break
    fi
done

if [ -z "$LUKS_PART" ]; then
    echo "No LUKS partition selected."
    exit 1
fi

echo "[+] Detecting network interfaces..."

mapfile -t IFACES < <(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

if [ "${#IFACES[@]}" -eq 0 ]; then
    echo "No network interfaces detected."
    exit 1
fi

echo "Available interfaces:"
select IFACE in "${IFACES[@]}"; do
    if [ -n "$IFACE" ]; then
        break
    fi
done

if [ -z "$IFACE" ]; then
    echo "No interface selected."
    exit 1
fi

echo "[+] Configuring initramfs network (DHCP)..."

sed -i '/^DEVICE=/d' /etc/initramfs-tools/initramfs.conf
sed -i '/^IP=/d' /etc/initramfs-tools/initramfs.conf

echo "DEVICE=$IFACE" >> /etc/initramfs-tools/initramfs.conf
echo "IP=dhcp" >> /etc/initramfs-tools/initramfs.conf

echo "[+] Adding HTTP key to LUKS partition..."
cryptsetup luksAddKey "$LUKS_PART" "$KEY_TMP"

echo "[+] Creating initramfs hook for curl..."

cat > /etc/initramfs-tools/hooks/curl <<EOF
#!/bin/sh
. /usr/share/initramfs-tools/hook-functions
copy_exec /usr/bin/curl
EOF

chmod +x /etc/initramfs-tools/hooks/curl

echo "[+] Creating HTTP keyscript..."

cat > /lib/cryptsetup/scripts/httpkey <<EOF
#!/bin/sh

KEYURL="$URL"
IFACE="$IFACE"
NET_TIMEOUT="$NET_TIMEOUT"
PASS_TIMEOUT="$PASS_TIMEOUT"

PATH=/sbin:/bin:/usr/sbin:/usr/bin

COUNT=0
while [ \$COUNT -lt \$NET_TIMEOUT ]; do
    if ip addr show "\$IFACE" 2>/dev/null | grep -q "inet "; then
        break
    fi
    sleep 1
    COUNT=\$((COUNT+1))
done

if ip addr show "\$IFACE" 2>/dev/null | grep -q "inet "; then
    if curl -fsS "\$KEYURL" >/tmp/lukskey 2>/dev/null; then
        if [ -s /tmp/lukskey ]; then
            cat /tmp/lukskey
            rm -f /tmp/lukskey
            exit 0
        fi
    fi
fi

( sleep "\$PASS_TIMEOUT" && echo b > /proc/sysrq-trigger ) &
TIMER_PID=\$!

PASS=\$(/lib/cryptsetup/askpass "Connection to keyserver failed. LUKS unlock: ")
RET=\$?

kill "\$TIMER_PID" 2>/dev/null
wait "\$TIMER_PID" 2>/dev/null

if [ "\$RET" -eq 0 ] && [ -n "\$PASS" ]; then
    printf "%s" "\$PASS"
    exit 0
fi

exit 1
EOF

chmod 700 /lib/cryptsetup/scripts/httpkey

echo "[+] Updating /etc/crypttab to use keyscript..."

sed -i "/^$LUKS_NAME / s|\$|,keyscript=/lib/cryptsetup/scripts/httpkey|" /etc/crypttab

echo "[+] Updating initramfs..."
update-initramfs -u -k all

echo
echo "=============================================="
echo "Setup complete."
echo
echo "LUKS partition: $LUKS_PART"
echo "Network interface: $IFACE"
echo "Key URL: $URL"
echo
echo "Reboot is required to test HTTP unlock."
echo "=============================================="
