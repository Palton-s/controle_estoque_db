#!/bin/bash
# Script para deploy da aplicação Controle de Estoque

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_DIR="/var/www/controle_estoque_db"
APP_USER="www-data"

echo -e "${GREEN}=== DEPLOY DA APLICAÇÃO CONTROLE DE ESTOQUE ===${NC}"

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script deve ser executado como root (sudo)${NC}" 
   exit 1
fi

# Verificar se o diretório existe
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}Diretório $APP_DIR não existe. Execute primeiro o install_apache.sh${NC}"
    exit 1
fi

echo -e "${GREEN}1. Fazendo backup da aplicação atual...${NC}"
if [ -d "$APP_DIR/app.py" ]; then
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p /backup/controle_estoque_db
    tar -czf "/backup/controle_estoque_db/backup_$timestamp.tar.gz" -C "$APP_DIR" .
    echo "Backup criado: /backup/controle_estoque_db/backup_$timestamp.tar.gz"
fi

echo -e "${GREEN}2. Parando serviços...${NC}"
systemctl stop apache2
supervisorctl stop controle-estoque

echo -e "${GREEN}3. Atualizando código da aplicação...${NC}"
# Assumindo que os arquivos estão no diretório atual
cp -r ./* $APP_DIR/

# Garantir que o wsgi.py está no lugar certo
if [ ! -f "$APP_DIR/wsgi.py" ]; then
    echo -e "${YELLOW}Criando wsgi.py...${NC}"
    cat > $APP_DIR/wsgi.py << 'EOL'
#!/usr/bin/env python3
import sys
import os

sys.path.insert(0, '/var/www/controle_estoque_db/')
os.environ['FLASK_APP'] = 'app.py'
os.environ['FLASK_ENV'] = 'production'

from app import app as application
application.config['DEBUG'] = False

if __name__ == "__main__":
    application.run()
EOL
fi

echo -e "${GREEN}4. Atualizando dependências...${NC}"
cd $APP_DIR
source venv/bin/activate
pip install -r requirements.txt

echo -e "${GREEN}5. Configurando permissões...${NC}"
chown -R $APP_USER:$APP_USER $APP_DIR
chmod -R 755 $APP_DIR
chmod -R 775 $APP_DIR/logs $APP_DIR/relatorios $APP_DIR/temp
chmod +x $APP_DIR/wsgi.py

echo -e "${GREEN}6. Verificando configuração do Apache...${NC}"

# Tentar diferentes comandos para verificar configuração do servidor web
if command -v httpd >/dev/null 2>&1; then
    httpd -t
    APACHE_TEST_RESULT=$?
elif command -v apache2ctl >/dev/null 2>&1; then
    apache2ctl configtest
    APACHE_TEST_RESULT=$?
elif command -v apachectl >/dev/null 2>&1; then
    apachectl configtest
    APACHE_TEST_RESULT=$?
else
    echo -e "${YELLOW}! Comando de teste do servidor web não encontrado, pulando verificação${NC}"
    APACHE_TEST_RESULT=0
fi

if [ $APACHE_TEST_RESULT -ne 0 ]; then
    echo -e "${RED}Erro na configuração do servidor web!${NC}"
    echo "Verifique manualmente a configuração antes de continuar"
    exit 1
fi

echo -e "${GREEN}7. Reiniciando serviços...${NC}"
# Detectar qual servidor web usar
if command -v httpd >/dev/null 2>&1 && systemctl is-active --quiet httpd; then
    echo "Recarregando httpd (sem reiniciar para não afetar outras aplicações)..."
    systemctl reload httpd
elif command -v apache2 >/dev/null 2>&1 && systemctl is-active --quiet apache2; then
    echo "Reiniciando apache2..."
    systemctl start apache2
else
    echo -e "${YELLOW}! Servidor web não detectado ou não está rodando${NC}"
fi

# Supervisor (se existir)
if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl start controle-estoque 2>/dev/null || echo "Supervisor não configurado ou não encontrado"
fi

echo -e "${GREEN}8. Verificando status...${NC}"
sleep 3

# Verificar status do servidor web
if systemctl is-active --quiet httpd; then
    echo -e "${GREEN}✓ httpd está rodando${NC}"
    systemctl status httpd --no-pager -l | head -10
elif systemctl is-active --quiet apache2; then
    echo -e "${GREEN}✓ apache2 está rodando${NC}"
    systemctl status apache2 --no-pager -l | head -10
else
    echo -e "${YELLOW}! Servidor web não está rodando${NC}"
fi

echo ""

# Verificar supervisor se existir
if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl status controle-estoque 2>/dev/null || echo "Supervisor não configurado"
else
    echo "Supervisor não instalado"
fi

echo -e "${GREEN}=== DEPLOY CONCLUÍDO ===${NC}"
echo -e "${YELLOW}Comandos para monitoramento:${NC}"
echo "- Logs Apache: tail -f /var/log/apache2/controle_estoque_error.log"
echo "- Logs App: tail -f $APP_DIR/logs/app.log"
echo "- Status: systemctl status apache2"
echo "- Teste: curl -I http://localhost/"