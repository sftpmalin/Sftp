<p align="center"><img src="https://raw.githubusercontent.com/bmartino1/unraid-docker-templates/refs/heads/main/images/SFTP.png" width="180"></p>
🚀 SFTP Malin – Version Folder

# 🔒 Serveur SFTP Sécurisé (Chroot) - Optimisé Unraid / TrueNAS

[![Docker Pulls](https://img.shields.io/docker/pulls/sftpmalin/sftp.svg)](https://hub.docker.com/r/sftpmalin/sftp)
[![Docker Image Size](https://img.shields.io/docker/image-size/sftpmalin/sftp.svg)](https://hub.docker.com/r/sftpmalin/sftp)
[![Multi-Arch](https://img.shields.io/badge/Architecture-ARMv7%20%7C%20ARM64%20%7C%20AMD64-blue)](https://hub.docker.com/r/sftpmalin/sftp)

Ce dépôt contient les images Docker et le script d'initialisation (`entrypoint.sh`) d'une solution SFTP **haute sécurité** conçue spécifiquement pour corriger les problèmes de **permissions (chown -R)** et de stabilité rencontrés sur les systèmes d'exploitation basés sur ZFS et BTRFS, comme **TrueNAS SCALE** et **Unraid**.

## ✨ Pourquoi choisir cette image ?

La solution `sftpmalin` garantit une séparation stricte des utilisateurs grâce à un **Chroot (cloisonnement total)** sans provoquer de conflits de propriété avec les volumes hôtes montés.

* **Sécurité Totale :** Chaque utilisateur est **enfermé (Chrooté)** dans son répertoire, empêchant l'accès aux dossiers des autres ou aux fichiers systèmes du Docker.
* **Compatibilité Hôte :** Utilisation d'une stratégie de permissions **non-récursive** pour ne jamais modifier la propriété des dossiers sur votre hôte (Unraid/TrueNAS).
* **Multi-Arch :** Support complet des architectures **ARMv7, ARM64, et AMD64/x86_64**.
* **Configuration Simple :** Gestion des utilisateurs, UID/GID et génération automatique des clés SSH via variables d'environnement.

---

## 🏗️ Les Deux Versions : HOME vs FOLDERS

Nous proposons deux versions pour répondre à différents besoins de déploiement :

### 1. Version SFTP HOME (Auto-Contenue)

| Tag | `sftpmalin/sftphome:latest` |
| :--- | :--- |
| **But** | La version la plus simple. Tous les utilisateurs stockent leurs données dans un **volume partagé unique** à l'intérieur du conteneur (`/data`). |
| **Dossier Final** | Chaque utilisateur voit et écrit uniquement dans `/Data` (qui est en réalité le dossier `/home/USER/Data` dans le conteneur). |
| **Permissions** | Gérées automatiquement par le script. **Aucune action n'est requise** sur l'hôte après le lancement du conteneur. |

### 2. Version SFTP FOLDERS (Avancée / Pro)

| Tag | `sftpmalin/sftp:latest` |
| :--- | :--- |
| **But** | Permet de lier directement le compte d'un utilisateur à un **dossier spécifique sur votre hôte** (ex: un partage Unraid). |
| **Dossier Final** | Chaque utilisateur se connecte et voit les données du volume monté sur `/home/USER/Data`. |
| **Permissions** | **⚠️ Nécessite une action de l'administrateur (vous).** Voir la section "Note Importante sur les Permissions". |

---

## 🛠️ Déploiement et Utilisation (Version FOLDERS)

### Variables d'Environnement

L'ajout des utilisateurs se fait via des variables numérotées. Le mot de passe est ignoré si l'authentification par clé est activée (`SSH_PASS_AUTH=no` par défaut).

| Variable | Exemple | Description |
| :--- | :--- | :--- |
| `USERS_VAR1` | `yoan:ignorer:1000:100` | Format : `user:motdepasse:UID:GID`. **UID et GID doivent correspondre** à ceux que vous souhaitez sur le volume hôte. |
| `USERS_VAR2` | `antoine:ignorer:1001:100` | Ajoutez autant de lignes `USERS_VAR` que nécessaire. |
| `KEY_VAR` | `3072` | Force la taille de la clé SSH générée. |

### Note Importante sur les Permissions (Version FOLDERS UNIQUEMENT)

Dans cette version, le conteneur crée le compte utilisateur avec un certain UID/GID. Pour que cet utilisateur puisse écrire dans le dossier hôte monté, **vous (l'administrateur) devez vous assurer que le dossier hôte** a les droits d'écriture pour cet UID/GID.

**Exemple d'action de l'administrateur sur l'hôte :**

Si l'utilisateur `yoan` a l'UID `1000` et vous montez `/mnt/user/Yoan_Share` dans le conteneur, vous devez vous assurer sur l'hôte (Unraid/TrueNAS) que :
1.  Le dossier `/mnt/user/Yoan_Share` est monté dans le conteneur à l'emplacement exact : **`/home/yoan/Data`**.
2.  Le dossier `/mnt/user/Yoan_Share` sur l'hôte appartient à l'UID `1000` (ou au GID `100`).

### Exemple de Commande `docker run` (SFTP FOLDERS)

Ce déploiement monte des dossiers externes différents pour chaque utilisateur :

```bash
docker run -d \
  --name sftp-prod \
  -p 2222:22 \
  # Volume de configuration (obligatoire)
  -v /mnt/user/appdata/sftp_config:/data:rw \
  \
  # Montages spécifiques pour chaque utilisateur
  # Yoan verra le contenu de Yoan_Share quand il se connectera.
  -v /mnt/user/Yoan_Share:/home/yoan/Data:rw \
  # Antoine verra le contenu de Antoine_Projects quand il se connectera.
  -v /mnt/user/Antoine_Projects:/home/antoine/Data:rw \
  \
  # Variables utilisateurs
  -e USERS_VAR1="yoan:ignorer:1000:100" \
  -e USERS_VAR2="antoine:ignorer:1001:100" \
  \
  sftpmalin/sftp:latest

🔑 Récupération des Clés SSH

Par défaut, l'authentification par mot de passe est désactivée. Les clés privées générées pour chaque utilisateur sont stockées dans le volume de configuration :

[Votre Volume /data]/private_keys/USER_ssh_key

Vous devrez récupérer ce fichier et le charger dans votre client SFTP (FileZilla, WinSCP, etc.) pour vous connecter.

🤝 Contribuer

Les retours et les contributions sont les bienvenus. N'hésitez pas à signaler un problème ou à proposer une amélioration sur ce dépôt GitHub.

⚙️ Déploiement et Utilisation (Exemples Complets)

Ces commandes incluent tous les paramètres réseau (--net='br0', --ip, -p) et de sécurité (-e SSH_PASS_AUTH="no") validés.

1. Version SFTP FOLDERS (Avancée / Pro)

Utilisée pour lier chaque compte à un dossier spécifique sur votre hôte (Unraid/TrueNAS). Requiert que l'administrateur gère les permissions UID/GID sur les dossiers montés.
Bash

docker run -d \
  --name sftp-folders \
  --hostname Sftp \
  --restart=unless-stopped \
  --net='br0' \
  --ip='192.168.1.53' \
  --pids-limit 2048 \
  -p 2222:22 \
  -v /mnt/user/appdata/sftp:/data:rw \
  \
  # Montages spécifiques pour chaque utilisateur
  -v /mnt/user/user1:/home/user1/Data:rw \
  -v /mnt/user/user2:/home/user2/Data:rw \
  -v /mnt/user/user3:/home/user3/Data:rw \
  -v /mnt/user/user4:/home/user4/Data:rw \
  -v /mnt/user/user5:/home/user5/Data:rw \
  -v /mnt/user/user6:/home/user6/Data:rw \
  \
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

2. Version SFTP HOME (Auto-Contenue)

Utilisée pour un déploiement simple où toutes les données des utilisateurs sont stockées à l'intérieur du volume /data (Auto-géré).
Bash

docker run -d \
  --name sftpHome \
  --hostname SftpHome \
  --restart=unless-stopped \
  --net='br0' \
  --ip='192.168.1.52' \
  -p 2222:22 \
  -v /mnt/user/appdata/sftphome:/data:rw \
  \
  -e USERS_VAR1="user1:0000:1000:100" \
  -e USERS_VAR2="user2:0000:1001:100" \
  -e USERS_VAR3="user3:0000:1002:100" \
  -e USERS_VAR4="user4:0000:1003:100" \
  -e USERS_VAR5="user5:0000:1004:100" \
  -e USERS_VAR6="user6:0000:1005:100" \
  -e KEY_VAR="3072" \
  \
  -e SSH_PASS_AUTH="no" \
  -e SSH_PERMIT_ROOT="no" \
  -e SSH_CHALLENGE_AUTH="no" \
  -e SSH_EMPTY_PASS="no" \
  -e SSH_USE_PAM="yes" \
  -e SSH_TCP_FORWARD="yes" \
  -e SSH_X11_FORWARD="yes" \
  -e SSH_PUBKEY_AUTH="yes" \
  sftpmalin/sftphome:latest
