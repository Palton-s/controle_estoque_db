#!/bin/bash
# Script para identificar e resolver conflito de Virtual Host

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== RESOLUÇÃO DE CONFLITO DE VIRTUAL HOST ===${NC}"

echo -e "${YELLOW}1. Identificando Virtual Host conflitante:${NC}"
echo "Virtual Host existente:"
httpd -S | grep -A5 -B5 "VirtualHost"

echo -e "\n${YELLOW}2. Verificando arquivo conflitante:${NC}"
VHOST_FILE="/etc/httpd/conf/extra/httpd-vhosts.conf"
if [ -f "$VHOST_FILE" ]; then
    echo "Conteúdo de $VHOST_FILE:"
    cat "$VHOST_FILE"
else
    echo "Arquivo não encontrado: $VHOST_FILE"
fi

echo -e "\n${YELLOW}3. Verificando configuração principal:${NC}"
grep -n "Include.*vhosts" /etc/httpd/conf/httpd.conf || echo "Include de vhosts não encontrado"

echo -e "\n${YELLOW}Soluções disponíveis:${NC}"
echo "A) Adicionar nossa aplicação ao Virtual Host existente"
echo "B) Desabilitar o Virtual Host existente"  
echo "C) Modificar a prioridade"

read -p "Escolha uma opção (A/B/C): " OPCAO

case $OPCAO in
    A|a)
        echo -e "\n${YELLOW}=== OPÇÃO A: Adicionando ao Virtual Host existente ===${NC}"
        
        # Backup do arquivo original
        cp "$VHOST_FILE" "$VHOST_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Adicionar nossa configuração ao Virtual Host existente
        cat >> "$VHOST_FILE" << 'EOL'

# Configuração adicionada para Controle de Estoque
WSGIDaemonProcess controle_estoque python-path=/var/www/controle_estoque_db python-home=/var/www/controle_estoque_db/venv
WSGIScriptAlias /estoque /var/www/controle_estoque_db/wsgi.py

<Directory /var/www/controle_estoque_db>
    WSGIProcessGroup controle_estoque
    WSGIApplicationGroup %{GLOBAL}
    Require all granted
</Directory>

Alias /estoque/static /var/www/controle_estoque_db/static
<Directory /var/www/controle_estoque_db/static>
    Require all granted
</Directory>
EOL
        ;;
        
    B|b)
        echo -e "\n${YELLOW}=== OPÇÃO B: Desabilitando Virtual Host conflitante ===${NC}"
        
        # Comentar a linha Include no httpd.conf
        sed -i 's/^Include.*httpd-vhosts.conf/#&/' /etc/httpd/conf/httpd.conf
        
        echo "Virtual Host desabilitado. Nossa configuração em conf.d/ será usada."
        ;;
        
    C|c)
        echo -e "\n${YELLOW}=== OPÇÃO C: Modificando prioridade ===${NC}"
        
        # Renomear nosso arquivo para ter prioridade
        mv /etc/httpd/conf.d/estoque.conf /etc/httpd/conf.d/000-estoque.conf
        
        echo "Arquivo renomeado para ter prioridade de carregamento."
        ;;
        
    *)
        echo "Opção inválida"
        exit 1
        ;;
esac

# Testar configuração
echo -e "\n${YELLOW}Testando nova configuração:${NC}"
httpd -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Configuração válida${NC}"
    
    # Reiniciar httpd
    echo -e "${YELLOW}Reiniciando httpd...${NC}"
    systemctl restart httpd
    
    # Aguardar e testar
    sleep 3
    echo -e "${YELLOW}Testando acesso:${NC}"
    curl -s -I http://localhost/estoque/ | head -1
    
else
    echo -e "${RED}✗ Erro na configuração${NC}"
    exit 1
fi

echo -e "\n${GREEN}=== CORREÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}Teste agora:${NC} http://localhost/estoque/"