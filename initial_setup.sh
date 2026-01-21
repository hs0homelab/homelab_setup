#!/bin/bash

# --- Configurações Iniciais ---
ANSIBLE_VAULT_PASS_FILE="secrets/vault_pass.txt"
VAULT_FILE="group_vars/all/vault.yml"
HOST_VARS_FILE="host_vars/homelab.yml"
INVENTORY_FILE="inventory.ini"

echo "--- Início da Configuração do Homelab ---"

# 1. Verificar e instalar Ansible (se necessário)
if ! command -v ansible &> /dev/null
then
    echo "Ansible não encontrado. A instalar..."
    sudo apt update
    sudo apt install -y python3 python3-pip git jq curl
    pip3 install ansible
    echo "Ansible instalado."
fi

# 2. Perguntar para criar um novo utilizador sudo
read -p "Deseja criar um novo utilizador sudo? (s/n): " create_user_choice
if [[ "$create_user_choice" =~ ^[Ss]$ ]]; then
    read -p "Nome do novo utilizador sudo: " NEW_SUDO_USER
    read -s -p "Password para o novo utilizador sudo: " NEW_SUDO_PASSWORD
    echo ""
    read -s -p "Repita a password: " NEW_SUDO_PASSWORD_CONFIRM
    echo ""

    if [ "$NEW_SUDO_PASSWORD" != "$NEW_SUDO_PASSWORD_CONFIRM" ]; then
        echo "Passwords não coincidem. A sair."
        exit 1
    fi
else
    echo "Não será criado um novo utilizador sudo. Certifique-se de que o utilizador atual tem privilégios sudo."
    NEW_SUDO_USER=$(whoami) # Usa o utilizador atual como sudo user para o Ansible
    NEW_SUDO_PASSWORD="" # Não será usada se o utilizador já existir
fi

# 3. Perguntar credenciais Samba
read -p "Nome de utilizador para a partilha Samba (e backup SMB): " SAMBA_USER
read -s -p "Password para o utilizador Samba (e backup SMB): " SAMBA_PASSWORD
echo ""
read -s -p "Repita a password: " SAMBA_PASSWORD_CONFIRM
echo ""

if [ "$SAMBA_PASSWORD" != "$SAMBA_PASSWORD_CONFIRM" ]; then
    echo "Passwords Samba não coincidem. A sair."
    exit 1
fi

# 4. Perguntar chave de autenticação Tailscale
read -s -p "Chave de autenticação Tailscale (authkey - https://login.tailscale.com/admin/settings/keys): " TAILSCALE_AUTH_KEY
echo ""

# 5. Perguntar credenciais Discord para notificações
read -p "Webhook URL do Discord para notificações: " DISCORD_WEBHOOK
read -p "ID do canal Discord para notificações (opcional, para embeds): " DISCORD_CHANNEL_ID
echo ""

# 6. Perguntar detalhes do servidor SMB de backup
read -p "Endereço IP do servidor SMB de backup (ex: 192.168.1.250): " BACKUP_SMB_HOST
read -p "Nome da partilha SMB no servidor de backup (ex: share): " BACKUP_SMB_SHARE

# --- Criar ou atualizar ficheiros de variáveis e vault ---

# Criar ficheiro de password do vault se não existir
if [ ! -f "$ANSIBLE_VAULT_PASS_FILE" ]; then
    read -s -p "Defina uma password para o Ansible Vault: " VAULT_PASSWORD
    echo ""
    echo "$VAULT_PASSWORD" > "$ANSIBLE_VAULT_PASS_FILE"
    chmod 600 "$ANSIBLE_VAULT_PASS_FILE"
    echo "Ficheiro de password do Ansible Vault criado."
else
    echo "Ficheiro de password do Ansible Vault já existe. Usando o existente."
fi

# Criar ou atualizar o ficheiro de vault encriptado
# As passwords serão encriptadas aqui
ansible-vault encrypt_string "$NEW_SUDO_PASSWORD" --name 'vault_new_sudo_password' --vault-password-file "$ANSIBLE_VAULT_PASS_FILE" > /tmp/new_sudo_password_vault.yml
ansible-vault encrypt_string "$SAMBA_PASSWORD" --name 'vault_samba_password' --vault-password-file "$ANSIBLE_VAULT_PASS_FILE" > /tmp/samba_password_vault.yml
ansible-vault encrypt_string "$TAILSCALE_AUTH_KEY" --name 'vault_tailscale_auth_key' --vault-password-file "$ANSIBLE_VAULT_PASS_FILE" > /tmp/tailscale_auth_key_vault.yml

# Criar/atualizar group_vars/all/vault.yml
echo "---" > "$VAULT_FILE"
cat /tmp/new_sudo_password_vault.yml >> "$VAULT_FILE"
cat /tmp/samba_password_vault.yml >> "$VAULT_FILE"
cat /tmp/tailscale_auth_key_vault.yml >> "$VAULT_FILE"
rm /tmp/new_sudo_password_vault.yml /tmp/samba_password_vault.yml /tmp/tailscale_auth_key_vault.yml
echo "Ficheiro de vault atualizado."

# Criar/atualizar host_vars/homelab.yml
echo "---" > "$HOST_VARS_FILE"
echo "new_sudo_user: \"$NEW_SUDO_USER\"" >> "$HOST_VARS_FILE"
echo "samba_user: \"$SAMBA_USER\"" >> "$HOST_VARS_FILE"
echo "samba_share_path: \"/mnt/share\"" >> "$HOST_VARS_FILE"
echo "discord_webhook_url: \"$DISCORD_WEBHOOK\"" >> "$HOST_VARS_FILE"
echo "discord_channel_id: \"$DISCORD_CHANNEL_ID\"" >> "$HOST_VARS_FILE"
echo "backup_target_smb_host: \"$BACKUP_SMB_HOST\"" >> "$HOST_VARS_FILE"
echo "backup_target_smb_share: \"$BACKUP_SMB_SHARE\"" >> "$HOST_VARS_FILE"
echo "backup_user: \"$SAMBA_USER\"" >> "$HOST_VARS_FILE" # Usar o mesmo user para backup
echo "backup_password: \"{{ vault_samba_password }}\"" >> "$HOST_VARS_FILE" # Usar a mesma password encriptada
echo "Ficheiro de variáveis do host atualizado."

# Atualizar inventory.ini com o utilizador inicial
sed -i "s/^homelab ansible_host=127.0.0.1 ansible_connection=local ansible_user=.*/homelab ansible_host=127.0.0.1 ansible_connection=local ansible_user=$NEW_SUDO_USER/" "$INVENTORY_FILE"


echo "--- A iniciar a execução do Ansible Playbook ---"
ansible-playbook playbooks/main.yml --vault-password-file "$ANSIBLE_VAULT_PASS_FILE"

echo "--- Configuração do Homelab Concluída ---"
