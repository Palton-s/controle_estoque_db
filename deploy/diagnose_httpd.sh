#!/bin/bash
# Script para diagnosticar problemas de configuração do httpd

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== DIAGNÓSTICO DA CONFIGURAÇÃO HTTPD ===${NC}"

# 1. Verificar se httpd está rodando
echo -e "${YELLOW}1. Status do httpd:${NC}"
systemctl status httpd --no-pager -l | head -10

# 2. Verificar arquivo de configuração
echo -e "\n${YELLOW}2. Verificar arquivo de configuração:${NC}"
CONF_FILE="/etc/httpd/conf.d/controle-estoque.conf"
if [ -f "$CONF_FILE" ]; then
    echo -e "${GREEN}✓ Arquivo existe: $CONF_FILE${NC}"
    echo "Conteúdo:"
    cat "$CONF_FILE"
else
    echo -e "${RED}✗ Arquivo não encontrado: $CONF_FILE${NC}"
fi

# 3. Verificar diretório da aplicação
echo -e "\n${YELLOW}3. Verificar aplicação:${NC}"
APP_DIR="/var/www/controle_estoque_db"
if [ -d "$APP_DIR" ]; then
    echo -e "${GREEN}✓ Diretório existe: $APP_DIR${NC}"
    echo "Arquivos principais:"
    ls -la "$APP_DIR" | grep -E "(wsgi\.py|app\.py)"
else
    echo -e "${RED}✗ Diretório não encontrado: $APP_DIR${NC}"
fi

# 4. Testar configuração do httpd
echo -e "\n${YELLOW}4. Testar configuração do httpd:${NC}"
httpd -t
echo "Resultado do teste: $?"

# 5. Verificar mod_wsgi
echo -e "\n${YELLOW}5. Verificar mod_wsgi:${NC}"
httpd -M | grep -i wsgi
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ mod_wsgi está carregado${NC}"
else
    echo -e "${RED}✗ mod_wsgi NÃO está carregado${NC}"
fi

# 6. Verificar sintaxe da configuração
echo -e "\n${YELLOW}6. Verificar sintaxe específica:${NC}"
if [ -f "$CONF_FILE" ]; then
    httpd -t -f /etc/httpd/conf/httpd.conf -D DUMP_VHOSTS 2>/dev/null | grep -A5 -B5 estoque || echo "Configuração /estoque não encontrada"
fi

# 7. Verificar logs de erro
echo -e "\n${YELLOW}7. Últimos logs de erro do httpd:${NC}"
tail -n 20 /var/log/httpd/error_log 2>/dev/null || echo "Log de erro não encontrado"

echo -e "\n${YELLOW}=== COMANDOS PARA CORRIGIR ===${NC}"
echo "1. Recarregar httpd: systemctl reload httpd"
echo "2. Reiniciar httpd: systemctl restart httpd" 
echo "3. Verificar config: httpd -t"
echo "4. Ver logs: tail -f /var/log/httpd/error_log"