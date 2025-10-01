#!/bin/bash
# Script para transferir arquivos do projeto para o servidor

echo "=== PREPARANDO ARQUIVOS PARA TRANSFER PARA SERVIDOR ==="

# Este script deve ser executado no servidor Linux
# Os arquivos podem ser transferidos via:
# 1. SCP/SFTP
# 2. Git clone
# 3. Upload manual

SOURCE_REPO="https://github.com/Palton-s/controle_estoque_db.git"
TEMP_DIR="/tmp/controle_estoque_db"

echo "1. Clonando repositório..."
if [ -d "$TEMP_DIR" ]; then
    echo "Diretório temporário já existe, removendo..."
    rm -rf "$TEMP_DIR"
fi

git clone "$SOURCE_REPO" "$TEMP_DIR"

if [ $? -eq 0 ]; then
    echo "✓ Repositório clonado em $TEMP_DIR"
    
    echo "Arquivos disponíveis:"
    ls -la "$TEMP_DIR"
    
    echo ""
    echo "Agora execute: sudo ./deploy/setup_flask.sh"
else
    echo "❌ Erro ao clonar repositório"
    echo ""
    echo "Alternativa - transferir arquivos manualmente:"
    echo "1. Crie: mkdir -p /tmp/controle_estoque_db"
    echo "2. Copie os arquivos do Windows para /tmp/controle_estoque_db/"
    echo "3. Execute: sudo ./deploy/setup_flask.sh"
fi