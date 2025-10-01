#!/bin/bash
# Script para configurar manualmente o httpd para /estoque

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CONFIGURAÇÃO MANUAL HTTPD /estoque ===${NC}"

# Verificar se é root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Execute como root: sudo $0${NC}" 
   exit 1
fi

APP_DIR="/var/www/controle_estoque_db"
CONF_FILE="/etc/httpd/conf.d/controle-estoque.conf"

# 1. Criar diretório da aplicação se não existir
echo -e "${YELLOW}1. Verificando diretório da aplicação...${NC}"
if [ ! -d "$APP_DIR" ]; then
    echo "Criando diretório $APP_DIR"
    mkdir -p "$APP_DIR"
    mkdir -p "$APP_DIR"/{logs,relatorios,temp,static,templates,utils}
    chown -R apache:apache "$APP_DIR"
fi

# 2. Verificar mod_wsgi
echo -e "${YELLOW}2. Verificando mod_wsgi...${NC}"
if ! httpd -M 2>/dev/null | grep -q wsgi; then
    echo "Instalando mod_wsgi..."
    yum install -y python3-mod_wsgi || dnf install -y python3-mod_wsgi
    
    # Criar arquivo de módulo se necessário
    if [ ! -f "/etc/httpd/conf.modules.d/10-wsgi.conf" ]; then
        WSGI_SO=$(find /usr/lib64/httpd/modules /usr/lib/httpd/modules -name "*wsgi*" 2>/dev/null | head -1)
        if [ -n "$WSGI_SO" ]; then
            echo "LoadModule wsgi_module $WSGI_SO" > /etc/httpd/conf.modules.d/10-wsgi.conf
        fi
    fi
fi

# 3. Criar configuração simples
echo -e "${YELLOW}3. Criando configuração...${NC}"
cat > "$CONF_FILE" << 'EOL'
# Configuração para Controle de Estoque em /estoque

# Carregar mod_wsgi se não estiver carregado
LoadModule wsgi_module modules/mod_wsgi.so

# Configuração WSGI
WSGIDaemonProcess controle_estoque python-path=/var/www/controle_estoque_db python-home=/var/www/controle_estoque_db/venv
WSGIScriptAlias /estoque /var/www/controle_estoque_db/wsgi.py

# Diretório da aplicação
<Directory /var/www/controle_estoque_db>
    WSGIProcessGroup controle_estoque
    WSGIApplicationGroup %{GLOBAL}
    Require all granted
    Options -Indexes
</Directory>

# Arquivos estáticos
Alias /estoque/static /var/www/controle_estoque_db/static
<Directory /var/www/controle_estoque_db/static>
    Require all granted
    Options -Indexes
</Directory>

# Relatórios
Alias /estoque/relatorios /var/www/controle_estoque_db/relatorios
<Directory /var/www/controle_estoque_db/relatorios>
    Require all granted
    Options -Indexes
</Directory>
EOL

# 4. Criar wsgi.py básico se não existir
echo -e "${YELLOW}4. Criando wsgi.py...${NC}"
if [ ! -f "$APP_DIR/wsgi.py" ]; then
    cat > "$APP_DIR/wsgi.py" << 'EOL'
#!/usr/bin/env python3
import sys
import os

# Adicionar o diretório da aplicação ao Python path
sys.path.insert(0, '/var/www/controle_estoque_db/')

# Definir variáveis de ambiente
os.environ['FLASK_APP'] = 'app.py'
os.environ['FLASK_ENV'] = 'production'

# Configuração para subdiretório
class ReverseProxied(object):
    def __init__(self, app, script_name=None):
        self.app = app
        self.script_name = script_name

    def __call__(self, environ, start_response):
        script_name = self.script_name
        if script_name:
            environ['SCRIPT_NAME'] = script_name
            path_info = environ['PATH_INFO']
            if path_info.startswith(script_name):
                environ['PATH_INFO'] = path_info[len(script_name):]
        return self.app(environ, start_response)

try:
    from app import app as application
    application.config['DEBUG'] = False
    application = ReverseProxied(application, script_name='/estoque')
except ImportError:
    # Aplicação de teste se app.py não existir
    from flask import Flask
    application = Flask(__name__)
    
    @application.route('/')
    def hello():
        return '<h1>Controle de Estoque - Configuração OK!</h1><p>A aplicação principal não foi encontrada. Copie os arquivos app.py e outros para /var/www/controle_estoque_db/</p>'
    
    application = ReverseProxied(application, script_name='/estoque')

if __name__ == "__main__":
    application.run()
EOL
fi

# 5. Ajustar permissões
echo -e "${YELLOW}5. Ajustando permissões...${NC}"
chown -R apache:apache "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod +x "$APP_DIR/wsgi.py"

# 6. Testar configuração
echo -e "${YELLOW}6. Testando configuração...${NC}"
httpd -t
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Configuração válida${NC}"
else
    echo -e "${RED}✗ Erro na configuração${NC}"
    exit 1
fi

# 7. Recarregar httpd
echo -e "${YELLOW}7. Recarregando httpd...${NC}"
systemctl reload httpd

# 8. Testar acesso
echo -e "${YELLOW}8. Testando acesso...${NC}"
sleep 2
curl -s -I http://localhost/estoque/ | head -1

echo -e "\n${GREEN}=== CONFIGURAÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}Teste no navegador:${NC} http://localhost/estoque/"
echo -e "${YELLOW}Logs de erro:${NC} tail -f /var/log/httpd/error_log"
echo -e "${YELLOW}Status httpd:${NC} systemctl status httpd"