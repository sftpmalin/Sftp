#!/bin/bash
set -e

# ============================================================
#    SCRIPT SFTP - VERSION FINAL "CHIRURGICALE"
#    (Respecte les montages Unraid - Pas de chown récursif)
# ============================================================

# --- 1. CONFIGURATION ---
SSH_PERMIT_ROOT="${SSH_PERMIT_ROOT:-no}"
SSH_PUBKEY_AUTH="${SSH_PUBKEY_AUTH:-yes}"
SSH_PASS_AUTH="${SSH_PASS_AUTH:-no}"
SSH_CHALLENGE_AUTH="${SSH_CHALLENGE_AUTH:-no}"
SSH_EMPTY_PASS="${SSH_EMPTY_PASS:-no}"
SSH_USE_PAM="${SSH_USE_PAM:-yes}"
SSH_TCP_FORWARD="${SSH_TCP_FORWARD:-yes}"
SSH_X11_FORWARD="${SSH_X11_FORWARD:-yes}"

USERS_CONF_FILE="/data/config/users.conf"

# --- 2. INITIALISATION ---
if [ ! -d "/data/config" ]; then
    echo "--- Première exécution : Initialisation ---"
    mkdir -p /data/config /data/keys /data/userkeys /data/private_keys

    echo "Génération du sshd_config (SFTP Cloisonné)..."
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

# ISOLATION STRICTE (Chroot)
Match User *,!root,!main
    ForceCommand internal-sftp -d /home/%u/Data
EOT
fi

# --- 3. TRAITEMENT DES VARIABLES (USERS_VAR1, 2, etc.) ---
echo "--- Mise à jour users.conf ---"
echo "# Format: user:pass:UID:GID" > "$USERS_CONF_FILE"

FOUND_USERS=false
# On récupère et trie les variables d'environnement
for VAR_NAME in $(env | grep -E '^USERS_VAR[0-9]+=' | sort -V); do
    USER_LINE="${VAR_NAME#*=}"
    if [ -n "$USER_LINE" ]; then
        echo "Ajout depuis variable : $USER_LINE"
        echo "$USER_LINE" >> "$USERS_CONF_FILE"
        FOUND_USERS=true
    fi
done

if ! $FOUND_USERS; then
    if [ $(wc -l < "$USERS_CONF_FILE") -le 1 ]; then 
        echo "--- Aucune variable trouvée, configuration par défaut ---"
        cat <<EOT >> "$USERS_CONF_FILE"
user1:ignored:1000:100
user2:ignored:1001:100
EOT
    fi
fi

# --- 4. CLÉS SERVEUR ---
if [ ! -f "/data/keys/ssh_host_rsa_key" ]; then
    echo "Génération clés hôte..."
    ssh-keygen -t rsa -b 4096 -f /data/keys/ssh_host_rsa_key -N ""
    ssh-keygen -t ecdsa -f /data/keys/ssh_host_ecdsa_key -N ""
    ssh-keygen -t ed25519 -f /data/keys/ssh_host_ed25519_key -N ""
fi

chmod 600 /data/keys/*_key || true
chmod 644 /data/keys/*.pub || true

rm -f /etc/ssh/ssh_host_*
ln -s /data/keys/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key
ln -s /data/keys/ssh_host_rsa_key.pub /etc/ssh/ssh_host_rsa_key.pub
ln -s /data/keys/ssh_host_ecdsa_key /etc/ssh/ssh_host_ecdsa_key
ln -s /data/keys/ssh_host_ecdsa_key.pub /etc/ssh/ssh_host_ecdsa_key.pub
ln -s /data/keys/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
ln -s /data/keys/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
ln -sf /data/config/sshd_config /etc/ssh/sshd_config

# --- 5. UTILISATEUR MAIN ---
if ! id "main" >/dev/null 2>&1; then
    groupadd -g 100 users || true
    useradd -N -s /bin/bash -u 9000 -g 100 main || true
    echo "main:unusable_pass_$(date +%s)" | chpasswd
fi

# --- 6. SYNCHRO UTILISATEURS ---
echo "Synchronisation des comptes..."
MIN_UID=1000

# A. Nettoyage
VALID_USERS=$(grep -vE "^#|^$" "$USERS_CONF_FILE" | cut -d: -f1 | xargs)
MANAGED_USERS=$(awk -F: -v min_uid="$MIN_UID" '$3 >= min_uid && $1 != "main" { print $1 }' /etc/passwd | xargs)
for user in $MANAGED_USERS; do
    if ! echo "$VALID_USERS" | grep -qw "$user"; then
        echo "Suppression obsolète: $user"
        deluser "$user"
    fi
done

# B. Création / Mise à jour (Lecture via FD3 pour sécurité stdin)
while IFS=: read -u 3 -r TARGET_USER TARGET_PASS TARGET_PUID TARGET_PGID || [ -n "$TARGET_USER" ]; do
    
    if [ -z "$TARGET_USER" ] || [[ "$TARGET_USER" = \#* ]]; then continue; fi

    echo "Traitement utilisateur : $TARGET_USER"
    TARGET_HOME_DIR="/home/$TARGET_USER"
    TARGET_DATA_DIR="$TARGET_HOME_DIR/Data"

    # Groupe
    if ! getent group "$TARGET_PGID" >/dev/null; then 
        addgroup --gid "$TARGET_PGID" "group-$TARGET_PGID" || true
    fi
    
    # User
    if ! getent passwd "$TARGET_PUID" >/dev/null; then
        adduser --disabled-password --gecos "" \
            --uid "$TARGET_PUID" --gid "$TARGET_PGID" \
            --home "$TARGET_HOME_DIR" \
            --shell "/bin/bash" "$TARGET_USER" || true
        
        echo "$TARGET_USER:unusable_pass_$(date +%s)_$RANDOM" | chpasswd
        echo "  -> Compte $TARGET_USER créé."
    fi
    
    # Structure Dossiers
    mkdir -p "$TARGET_HOME_DIR/.ssh"
    mkdir -p "$TARGET_DATA_DIR"
    if [ ! -f "$TARGET_HOME_DIR/.profile" ]; then touch "$TARGET_HOME_DIR/.profile"; fi

    # Clés SSH Utilisateur
    PUB_KEY_FILE="/data/userkeys/$TARGET_USER.pub"
    PRIVATE_KEY_FILE_PATH="/data/private_keys/${TARGET_USER}_ssh_key"
    KEY_VAR="${KEY_VAR:-3072}"

    if [ ! -f "$PUB_KEY_FILE" ]; then
        echo "  -> Génération clés ($KEY_VAR)..."
        case "$KEY_VAR" in
            2048)       ssh-keygen -t rsa -b 2048 -f "$PRIVATE_KEY_FILE_PATH" -N "" < /dev/null ;;
            4096)       ssh-keygen -t rsa -b 4096 -f "$PRIVATE_KEY_FILE_PATH" -N "" < /dev/null ;;
            [Ee]d25519) ssh-keygen -t ed25519 -f "$PRIVATE_KEY_FILE_PATH" -N "" < /dev/null ;;
            *)          ssh-keygen -t rsa -b 3072 -f "$PRIVATE_KEY_FILE_PATH" -N "" < /dev/null ;;
        esac
        mv "${PRIVATE_KEY_FILE_PATH}.pub" "$PUB_KEY_FILE"
        chmod 600 "$PRIVATE_KEY_FILE_PATH" || true 

        if command -v puttygen >/dev/null; then
             puttygen "$PRIVATE_KEY_FILE_PATH" -O private -o "${PRIVATE_KEY_FILE_PATH}.ppk" || true
        fi
    fi

    # Installation Clé Publique
    if [ -f "$PUB_KEY_FILE" ]; then
        cat "$PUB_KEY_FILE" | tr -d '\r' > "$TARGET_HOME_DIR/.ssh/authorized_keys"
    else
        rm -f "$TARGET_HOME_DIR/.ssh/authorized_keys"
    fi

    # ==================================================================
    # [PERMISSION FIX] LE MODE CHIRURGICAL
    # On ne touche PAS au dossier Data (volume Unraid) en mode chown
    # ==================================================================
    
    # 1. On change le propriétaire du dossier HOME uniquement (PAS récursif)
    # Cela évite l'erreur "Operation not permitted" sur le sous-dossier Data
    chown "$TARGET_PUID":"$TARGET_PGID" "$TARGET_HOME_DIR" || true
    
    # 2. On change le propriétaire du dossier .ssh (interne) en Récursif
    chown -R "$TARGET_PUID":"$TARGET_PGID" "$TARGET_HOME_DIR/.ssh" || true

    # 3. Droits stricts sur les dossiers internes
    chmod 700 "$TARGET_HOME_DIR" || true
    chmod 700 "$TARGET_HOME_DIR/.ssh" || true
    [ -f "$TARGET_HOME_DIR/.ssh/authorized_keys" ] && chmod 600 "$TARGET_HOME_DIR/.ssh/authorized_keys" || true
    
    # 4. On met juste les droits de lecture/execution sur Data (pas de chown)
    chmod 755 "$TARGET_DATA_DIR" || true
    
    # Config .profile (PATH et Umask)
    if ! grep -q "umask 022" "$TARGET_HOME_DIR/.profile"; then echo "umask 022" >> "$TARGET_HOME_DIR/.profile"; fi
    PATH_STRING='export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games"'
    if ! grep -q "$PATH_STRING" "$TARGET_HOME_DIR/.profile"; then echo "$PATH_STRING" >> "$TARGET_HOME_DIR/.profile"; fi

done 3< <(tail -n +2 "$USERS_CONF_FILE")

# --- 7. SÉCURITÉ CONFIG ---
chown -R 9000:100 /data/config || true
chmod 600 /data/config/sshd_config || true
chmod 600 /data/config/users.conf || true

# --- 8. DÉMARRAGE ---
mkdir -p -m 0755 /run/sshd
echo "Démarrage SSH..."
exec "$@"