#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
SSH_PERMIT_ROOT="${SSH_PERMIT_ROOT:-no}"
SSH_PUBKEY_AUTH="${SSH_PUBKEY_AUTH:-yes}"
SSH_PASS_AUTH="${SSH_PASS_AUTH:-no}"
SSH_CHALLENGE_AUTH="${SSH_CHALLENGE_AUTH:-no}"
SSH_EMPTY_PASS="${SSH_EMPTY_PASS:-no}"
SSH_USE_PAM="${SSH_USE_PAM:-yes}"
SSH_TCP_FORWARD="${SSH_TCP_FORWARD:-yes}"
SSH_X11_FORWARD="${SSH_X11_FORWARD:-yes}"

USERS_VAR="${USERS_VAR:-}" 
USERS_CONF_FILE="/data/config/users.conf"

# --- 2. INITIALISATION ---
if [ ! -d "/data/config" ]; then
    echo "--- Première exécution : Initialisation ---"
    # Création du dossier /data/home pour stocker les utilisateurs
    mkdir -p /data/config /data/keys /data/userkeys /data/private_keys /data/home

    echo "Génération du sshd_config (Mode HOME Direct)..."
    cat <<EOT > /data/config/sshd_config
Port 22
Protocol 2
PermitRootLogin $SSH_PERMIT_ROOT
PubkeyAuthentication $SSH_PUBKEY_AUTH
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication $SSH_PASS_AUTH
ChallengeResponseAuthentication $SSH_CHALLENGE_AUTH
PermitEmptyPasswords $SSH_EMPTY_PASS
UsePAM $SSH_USE_PAM
Subsystem sftp internal-sftp
AllowTcpForwarding $SSH_TCP_FORWARD
X11Forwarding $SSH_X11_FORWARD
HostKey /data/keys/ssh_host_rsa_key
HostKey /data/keys/ssh_host_ecdsa_key
HostKey /data/keys/ssh_host_ed25519_key

# MODE HOME DIRECT (Pas de sous-dossier Data)
Match User *,!root,!main
    ForceCommand internal-sftp
EOT
fi

# --- 3. TRAITEMENT UTILISATEURS ---
if [ -n "$USERS_VAR" ]; then
    echo "--- Mise à jour users.conf ---"
    echo "# Format: user:pass:UID:GID" > "$USERS_CONF_FILE"
    printf "%b\n" "$USERS_VAR" >> "$USERS_CONF_FILE"
else
    if [ ! -f "$USERS_CONF_FILE" ]; then
        echo "--- Création users.conf par défaut ---"
        cat <<EOT > "$USERS_CONF_FILE"
# Format: user:pass:UID:GID
user1:ignored:1000:100
user2:ignored:1001:100
EOT
    fi
fi

# --- 4. CLÉS SERVEUR ---
if [ ! -f "/data/keys/ssh_host_rsa_key" ]; then
    ssh-keygen -t rsa -b 4096 -f /data/keys/ssh_host_rsa_key -N ""
    ssh-keygen -t ecdsa -f /data/keys/ssh_host_ecdsa_key -N ""
    ssh-keygen -t ed25519 -f /data/keys/ssh_host_ed25519_key -N ""
fi
chmod 600 /data/keys/*_key
chmod 644 /data/keys/*.pub
rm -f /etc/ssh/ssh_host_*
ln -s /data/keys/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key
ln -s /data/keys/ssh_host_rsa_key.pub /etc/ssh/ssh_host_rsa_key.pub
ln -s /data/keys/ssh_host_ecdsa_key /etc/ssh/ssh_host_ecdsa_key
ln -s /data/keys/ssh_host_ecdsa_key.pub /etc/ssh/ssh_host_ecdsa_key.pub
ln -s /data/keys/ssh_host_ed25519 /etc/ssh/ssh_host_ed25519_key
ln -s /data/keys/ssh_host_ed25519.pub /etc/ssh/ssh_host_ed25519_key.pub
ln -sf /data/config/sshd_config /etc/ssh/sshd_config

# --- 5. UTILISATEUR MAIN ---
if ! id "main" >/dev/null 2>&1; then
    groupadd -g 100 users || true
    useradd -N -s /bin/bash -u 9000 -g 100 main
    echo "main:unusable_pass_$(date +%s)" | chpasswd
fi

# --- 6. SYNCHRO UTILISATEURS ---
echo "Synchronisation..."
MIN_UID=1000

# A. Nettoyage
VALID_USERS=$(grep -vE "^#|^$" "$USERS_CONF_FILE" | cut -d: -f1 | xargs)
MANAGED_USERS=$(awk -F: -v min_uid="$MIN_UID" '$3 >= min_uid && $1 != "main" { print $1 }' /etc/passwd | xargs)
for user in $MANAGED_USERS; do
    if ! echo "$VALID_USERS" | grep -qw "$user"; then
        echo "Suppression: $user"
        deluser "$user"
    fi
done

# B. Création
tail -n +2 "$USERS_CONF_FILE" | while IFS=: read -r TARGET_USER TARGET_PASS TARGET_PUID TARGET_PGID || [ -n "$TARGET_USER" ]; do
    
    if [ -z "$TARGET_USER" ] || [[ "$TARGET_USER" = \#* ]]; then continue; fi

    echo "Traitement : $TARGET_USER"
    
    # [CRUCIAL] Le home est dans /data/home pour la persistance
    TARGET_HOME_DIR="/data/home/$TARGET_USER"

    if ! getent group "$TARGET_PGID" >/dev/null; then addgroup --gid "$TARGET_PGID" "group-$TARGET_PGID"; fi
    
    if ! getent passwd "$TARGET_PUID" >/dev/null; then
        adduser --disabled-password --gecos "" \
            --uid "$TARGET_PUID" --gid "$TARGET_PGID" \
            --home "$TARGET_HOME_DIR" \
            --shell "/bin/bash" "$TARGET_USER"
        echo "$TARGET_USER:unusable_pass_$(date +%s)_$RANDOM" | chpasswd
    fi
    
    mkdir -p "$TARGET_HOME_DIR/.ssh"
    # PAS de création de dossier 'Data' ici. C'est la version HOME pure.

    # CLÉS DYNAMIQUES
    PUB_KEY_FILE="/data/userkeys/$TARGET_USER.pub"
    PRIVATE_KEY_FILE_PATH="/data/private_keys/${TARGET_USER}_ssh_key"
    KEY_VAR="${KEY_VAR:-3072}"

    if [ ! -f "$PUB_KEY_FILE" ]; then
        echo "-> Génération clé ($KEY_VAR)..."
        case "$KEY_VAR" in
            2048)       ssh-keygen -t rsa -b 2048 -f "$PRIVATE_KEY_FILE_PATH" -N "" ;;
            4096)       ssh-keygen -t rsa -b 4096 -f "$PRIVATE_KEY_FILE_PATH" -N "" ;;
            [Ee]d25519) ssh-keygen -t ed25519 -f "$PRIVATE_KEY_FILE_PATH" -N "" ;;
            *)          ssh-keygen -t rsa -b 3072 -f "$PRIVATE_KEY_FILE_PATH" -N "" ;;
        esac
        mv "${PRIVATE_KEY_FILE_PATH}.pub" "$PUB_KEY_FILE"
        chmod 600 "$PRIVATE_KEY_FILE_PATH"
    fi

    if [ -f "$PUB_KEY_FILE" ]; then
        cat "$PUB_KEY_FILE" | dos2unix > "$TARGET_HOME_DIR/.ssh/authorized_keys"
    else
        rm -f "$TARGET_HOME_DIR/.ssh/authorized_keys"
    fi

    # PERMISSIONS (Tout à l'utilisateur)
    chown -R "$TARGET_PUID":"$TARGET_PGID" "$TARGET_HOME_DIR"
    chmod 700 "$TARGET_HOME_DIR"
    chmod 700 "$TARGET_HOME_DIR/.ssh"
    [ -f "$TARGET_HOME_DIR/.ssh/authorized_keys" ] && chmod 600 "$TARGET_HOME_DIR/.ssh/authorized_keys"

done

# --- 7. SÉCURITÉ CONFIG ---
chown -R 9000:100 /data/config
chmod 600 /data/config/sshd_config
chmod 600 /data/config/users.conf

# --- 8. RUN ---
mkdir -p -m 0755 /run/sshd
echo "Démarrage SSH..."
exec "$@"