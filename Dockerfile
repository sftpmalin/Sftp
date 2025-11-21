# Utiliser l'image Debian 12 (Bookworm) standard
FROM debian:12

# Définir l'argument pour l'installation non interactive
ARG DEBIAN_FRONTEND=noninteractive

# 1. Installation des dépendances (SYNTAXE CORRIGÉE)
RUN apt-get update && apt-get install -y \
    openssh-server \
    dos2unix \
    acl \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Copie du script d'entrée
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 3. Configuration réseau et volumes
EXPOSE 22

# /data est pour la configuration persistante (users.conf, host_keys, etc.)
# /home contiendra les dossiers .ssh des utilisateurs
VOLUME ["/data", "/home"]

# 4. Lancement
# Le script d'entrée s'exécutera en premier
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# La commande par défaut (passée à "exec" à la fin de votre script)
# Lance sshd en mode "ne pas détacher" (-D) et log vers stderr (-e)
CMD ["/usr/sbin/sshd", "-D", "-e"]