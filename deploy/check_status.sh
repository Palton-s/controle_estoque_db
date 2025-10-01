#!/bin/bash
# Script para verificar se a aplicação está funcionando corretamente

echo "=== VERIFICAÇÃO DO STATUS DA APLICAÇÃO ==="

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_DIR="/var/www/controle_estoque_db"
DOMAIN="localhost"  # ou seu domínio

echo -e "${YELLOW}1. Verificando servidor web...${NC}"
if systemctl is-active --quiet httpd; then
    echo -e "${GREEN}✓ httpd está rodando${NC}"
elif systemctl is-active --quiet apache2; then
    echo -e "${GREEN}✓ apache2 está rodando${NC}"
else
    echo -e "${RED}✗ Servidor web parado${NC}"
fi

echo -e "${YELLOW}2. Verificando configuração do servidor web...${NC}"
if command -v httpd >/dev/null 2>&1; then
    httpd -t 2>/dev/null
    CONFIG_RESULT=$?
elif command -v apache2ctl >/dev/null 2>&1; then
    apache2ctl configtest 2>/dev/null
    CONFIG_RESULT=$?
else
    CONFIG_RESULT=1
fi

if [ $CONFIG_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Configuração do servidor web OK${NC}"
else
    echo -e "${RED}✗ Erro na configuração do servidor web${NC}"
fi

echo -e "${YELLOW}3. Verificando aplicação...${NC}"
if [ -f "$APP_DIR/wsgi.py" ]; then
    echo -e "${GREEN}✓ WSGI file existe${NC}"
else
    echo -e "${RED}✗ WSGI file não encontrado${NC}"
fi

echo -e "${YELLOW}4. Verificando ambiente virtual...${NC}"
if [ -d "$APP_DIR/venv" ]; then
    echo -e "${GREEN}✓ Virtual environment existe${NC}"
else
    echo -e "${RED}✗ Virtual environment não encontrado${NC}"
fi

echo -e "${YELLOW}5. Testando resposta HTTP...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN/)
if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✓ Aplicação respondendo (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${RED}✗ Aplicação com problema (HTTP $HTTP_CODE)${NC}"
fi

echo -e "${YELLOW}6. Verificando logs de erro...${NC}"

# Tentar diferentes locais de log
ERROR_LOG=""
if [ -f "/var/log/httpd/controle_estoque_error.log" ]; then
    ERROR_LOG="/var/log/httpd/controle_estoque_error.log"
elif [ -f "/var/log/apache2/controle_estoque_error.log" ]; then
    ERROR_LOG="/var/log/apache2/controle_estoque_error.log"
fi

if [ -n "$ERROR_LOG" ]; then
    ERRORS=$(tail -n 50 "$ERROR_LOG" | grep -i error | wc -l)
    if [ "$ERRORS" -eq 0 ]; then
        echo -e "${GREEN}✓ Sem erros recentes nos logs${NC}"
    else
        echo -e "${YELLOW}! $ERRORS erros encontrados nos logs recentes${NC}"
        echo "Últimos erros:"
        tail -n 10 "$ERROR_LOG" | grep -i error
    fi
else
    echo -e "${YELLOW}! Log de erro não encontrado${NC}"
    echo "Procure em: /var/log/httpd/ ou /var/log/apache2/"
fi

echo -e "${YELLOW}7. Verificando permissões...${NC}"
OWNER=$(stat -c '%U' $APP_DIR)
if [ "$OWNER" == "www-data" ]; then
    echo -e "${GREEN}✓ Permissões OK (owner: $OWNER)${NC}"
else
    echo -e "${YELLOW}! Owner: $OWNER (esperado: www-data)${NC}"
fi

echo -e "${YELLOW}8. Verificando espaço em disco...${NC}"
DISK_USAGE=$(df -h $APP_DIR | awk 'NR==2{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "${GREEN}✓ Espaço em disco OK ($DISK_USAGE% usado)${NC}"
else
    echo -e "${YELLOW}! Espaço em disco baixo ($DISK_USAGE% usado)${NC}"
fi

echo ""
echo "=== INFORMAÇÕES ADICIONAIS ==="
echo "Data/Hora: $(date)"
echo "Uptime: $(uptime -p)"
echo "Versão Python: $(cd $APP_DIR && venv/bin/python --version 2>/dev/null || echo 'N/A')"
if command -v httpd >/dev/null 2>&1; then
    echo "Processos httpd: $(ps aux | grep -c httpd)"
else
    echo "Processos apache2: $(ps aux | grep -c apache2)"
fi

echo ""
echo "=== COMANDOS ÚTEIS ==="
if command -v httpd >/dev/null 2>&1; then
    echo "Ver logs de erro: sudo tail -f /var/log/httpd/controle_estoque_error.log"
    echo "Recarregar httpd: sudo systemctl reload httpd"
    echo "Status httpd: sudo systemctl status httpd"
    echo "Testar config: sudo httpd -t"
else
    echo "Ver logs de erro: sudo tail -f /var/log/apache2/controle_estoque_error.log"
    echo "Reiniciar apache2: sudo systemctl restart apache2"
    echo "Status apache2: sudo systemctl status apache2"
    echo "Testar config: sudo apache2ctl configtest"
fi