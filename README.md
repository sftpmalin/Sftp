<p align="center"><img src="https://raw.githubusercontent.com/bmartino1/unraid-docker-templates/refs/heads/main/images/SFTP.png" width="180"></p>
🚀 SFTP Malin – Version Folder

Serveur SFTP moderne, multi-utilisateurs, sécurisé, avec montage externe par utilisateur.

📘 Présentation

SFTP Malin – Version Folder est un conteneur SFTP autonome basé sur Debian 12, conçu pour :

🔐 SSH/SFTP sécurisé (authentification par clés)

👥 Multi-utilisateurs illimité

📁 Un dossier monté par utilisateur
(structure obligatoire /home/<user>/Data)

🔑 Génération automatique des clés SSH

⚙️ Configuration simple via variables d’environnement

💾 Compatibilité totale Unraid / Docker / Synology / Portainer

🎯 Cette version est destinée aux administrateurs qui veulent gérer manuellement les dossiers utilisateurs, chacun pointant vers un emplacement différent du NAS.

🆕 Nouvelle politique USERS_VARX (obligatoire)

Les utilisateurs doivent désormais être déclarés comme ceci :

✔️ Format obligatoire
username:password_unused:uid:gid

✔️ Exemple officiel
-e USERS_VAR1="user1:0000:1000:100" \
-e USERS_VAR2="user2:0000:1001:100" \
-e USERS_VAR3="user3:0000:1002:100" \
-e USERS_VAR4="user4:0000:1003:100" \
-e USERS_VAR5="user5:0000:1004:100" \


🎯 Pourquoi ?
Parce qu’Unraid, Synology et Docker Desktop interprètent mal les variables contenant plusieurs lignes.
Avec USERS_VARX, 0 bug, 100% compatible.

📁 Montages obligatoires

Chaque utilisateur doit avoir :

/mnt/.../userX  →  /home/userX/Data

✔️ Exemple exact :
-v /mnt/user/appdata/sftp:/data:rw \
-v /mnt/user/user1:/home/user1/Data:rw \
-v /mnt/user/user2:/home/user2/Data:rw \
-v /mnt/user/user3:/home/user3/Data:rw \
-v /mnt/user/user4:/home/user4/Data:rw \

🔒 Important – Comportement Unraid

Unraid interdit aux conteneurs de modifier les permissions des dossiers montés depuis :

/mnt/user


👉 Le conteneur ne touche plus aux permissions DATA.
👉 C’est à l’administrateur d’appliquer les bons UID/GID.

✔ Ce que le conteneur gère :

/home/<user>/.ssh

clés privées

clés publiques

authorized_keys

configuration interne

❌ Ce que l’admin doit gérer :

Les droits du dossier réel monté dans :

/home/<user>/Data

🚀 Exemple complet docker run OFFICIEL
docker run -d \
  --name sftp \
  --hostname Sftp \
  --restart=unless-stopped \
  --net='br0' \
  --ip='192.168.1.50' \
  --pids-limit 2048 \
  -p 2222:22 \
  -v /mnt/user/appdata/sftp:/data:rw \
  -v /mnt/user/user1:/home/user1/Data:rw \
  -v /mnt/user/user2:/home/user2/Data:rw \
  -v /mnt/user/user3:/home/user3/Data:rw \
  -v /mnt/user/user4:/home/user4/Data:rw \
  -e USERS_VAR1="user1:0000:1000:100" \
  -e USERS_VAR2="user2:0000:1001:100" \
  -e USERS_VAR3="user3:0000:1002:100" \
  -e USERS_VAR4="user4:0000:1003:100" \
  -e USERS_VAR5="user5:0000:1004:100" \
  -e KEY_VAR="3072" \
  -e SSH_PASS_AUTH="no" \
  -e SSH_PERMIT_ROOT="no" \
  -e SSH_CHALLENGE_AUTH="no" \
  -e SSH_EMPTY_PASS="no" \
  -e SSH_USE_PAM="yes" \
  -e SSH_TCP_FORWARD="yes" \
  -e SSH_X11_FORWARD="yes" \
  -e SSH_PUBKEY_AUTH="yes" \
sftpmalin/sftp:latest

🔑 Gestion automatique des clés

Pour chaque utilisateur, le conteneur génère :

/data/private_keys/<user>_ssh_key
/data/private_keys/<user>_ssh_key.pub
/home/<user>/.ssh/authorized_keys


✔ Sécurisé
✔ Persistant
✔ Automatique

🗂 Structure interne du volume /data
/data
├── config/
│   ├── sshd_config
│   └── users.conf
├── keys/                # clés du serveur SSH
├── private_keys/        # clés privées users
├── userkeys/            # clés publiques users
└── home/
    └── <user>/Data      # montage externe obligatoire

🧩 Variables SSH
SSH_PERMIT_ROOT=yes|no
SSH_PUBKEY_AUTH=yes|no
SSH_PASS_AUTH=yes|no
SSH_CHALLENGE_AUTH=yes|no
SSH_EMPTY_PASS=yes|no
SSH_USE_PAM=yes|no
SSH_TCP_FORWARD=yes|no
SSH_X11_FORWARD=yes|no


Recommandé :

-e SSH_PASS_AUTH="no" \
-e SSH_PERMIT_ROOT="no" \
-e SSH_PUBKEY_AUTH="yes" \

🔌 Connexion SFTP
sftp -P 2222 -i user1_ssh_key user1@IP

📦 Liens

🔗 Docker Hub
https://hub.docker.com/r/sftpmalin/sftp

🔗 GitHub (détails + scripts + support)
https://github.com/sftpmalin/Media-Remote-Convert

📝 Licence

MIT License
