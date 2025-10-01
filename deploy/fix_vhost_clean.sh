#!/bin/bash
# Script para corrigir configuração conflitante no Virtual Host

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CORREÇÃO DE CONFIGURAÇÃO CONFLITANTE ===${NC}"

VHOST_FILE="/etc/httpd/conf/extra/httpd-vhosts.conf"

# 1. Backup do arquivo atual
echo -e "${YELLOW}1. Fazendo backup da configuração atual...${NC}"
cp "$VHOST_FILE" "$VHOST_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# 2. Mostrar problema atual
echo -e "\n${YELLOW}2. Problemas identificados:${NC}"
echo -e "${RED}✗ WSGIDaemonProcess duplicado${NC}"
echo -e "${RED}✗ Duas aplicações WSGI conflitantes (/controle_estoque e /estoque)${NC}"
echo -e "${RED}✗ Configurações fora do Virtual Host${NC}"

# 3. Limpar configuração
echo -e "\n${YELLOW}3. Limpando configurações conflitantes...${NC}"

# Remover configurações duplicadas no final do arquivo
sed -i '/^# Configuração adicionada para Controle de Estoque/,$d' "$VHOST_FILE"

# 4. Adicionar configuração correta dentro do Virtual Host
echo -e "\n${YELLOW}4. Adicionando configuração correta...${NC}"

# Criar nova configuração limpa
cat > "$VHOST_FILE" << 'EOL'
# Virtual Hosts
#
# Required modules: mod_log_config

# If you want to maintain multiple domains/hostnames on your
# machine you can setup VirtualHost containers for them. Most configurations
# use only name-based virtual hosts so the server doesn't need to worry about
# IP addresses. This is indicated by the asterisks in the directives below.
#
# Please see the documentation at
# <URL:http://httpd.apache.org/docs/2.4/vhosts/>
# for further details before you try to setup virtual hosts.
#
# You may use the command line option '-S' to verify your virtual host
# configuration.

#
# VirtualHost example:
# Almost any Apache directive may go into a VirtualHost container.
# The first VirtualHost section is used for all requests that do not
# match a ServerName or ServerAlias in any <VirtualHost> block.
#
#<VirtualHost *:80>
#    ServerAdmin webmaster@dummy-host.example.com
#    DocumentRoot "/etc/httpd/docs/dummy-host.example.com"
#    ServerName dummy-host.example.com
#    ServerAlias www.dummy-host.example.com
#    ErrorLog "/var/log/httpd/dummy-host.example.com-error_log"
#    CustomLog "/var/log/httpd/dummy-host.example.com-access_log" common
#</VirtualHost>

<VirtualHost *:80>
    ServerAdmin webmaster@dummy-host2.example.com
    ServerName 164.41.170.85
    ServerAlias localhost

    # DocumentRoot principal
    DocumentRoot "/var/www/down_detector"

    ErrorLog "/var/log/httpd/error_log"
    CustomLog "/var/log/httpd/access_log" common

    <Directory /var/www/down_detector>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # Alias do bot
    Alias "/bot" "/opt/crawler-moodle/bot/"
    <Directory "/opt/crawler-moodle/bot/">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # CONFIGURAÇÃO CORRIGIDA - Controle de Estoque
    # Apenas UMA configuração WSGI
    WSGIDaemonProcess controle_estoque python-path=/var/www/controle_estoque_db python-home=/var/www/controle_estoque_db/venv
    WSGIProcessGroup controle_estoque
    WSGIScriptAlias /estoque /var/www/controle_estoque_db/wsgi.py

    <Directory /var/www/controle_estoque_db>
        WSGIApplicationGroup %{GLOBAL}
        Require all granted
        Options -Indexes
    </Directory>

    # Arquivos estáticos do Controle de Estoque
    Alias /estoque/static /var/www/controle_estoque_db/static
    <Directory /var/www/controle_estoque_db/static>
        Require all granted
        Options -Indexes
    </Directory>

    # Relatórios do Controle de Estoque
    Alias /estoque/relatorios /var/www/controle_estoque_db/relatorios
    <Directory /var/www/controle_estoque_db/relatorios>
        Require all granted
        Options -Indexes
    </Directory>

</VirtualHost>
EOL

# 5. Remover arquivos de configuração conflitantes em conf.d/
echo -e "\n${YELLOW}5. Removendo configurações conflitantes em conf.d/...${NC}"
rm -f /etc/httpd/conf.d/estoque.conf
rm -f /etc/httpd/conf.d/000-estoque.conf
rm -f /etc/httpd/conf.d/controle-estoque.conf

# 6. Criar wsgi.py funcional
echo -e "\n${YELLOW}6. Criando wsgi.py corrigido...${NC}"
cat > /var/www/controle_estoque_db/wsgi.py << 'EOL'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WSGI Configuration for Controle de Estoque
Configurado para rodar em /estoque
"""

import sys
import os

# Adicionar o diretório da aplicação ao Python path
sys.path.insert(0, '/var/www/controle_estoque_db/')

# Definir variáveis de ambiente necessárias
os.environ['FLASK_APP'] = 'app.py'
os.environ['FLASK_ENV'] = 'production'

# Middleware para subdiretório
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
    # Tentar importar aplicação Flask real
    from app import app as application
    application.config['DEBUG'] = False
    application.config['TESTING'] = False
    # Aplicar middleware para subdiretório
    application = ReverseProxied(application, script_name='/estoque')
    
except ImportError as e:
    # Se app.py não existir, criar aplicação de teste
    from flask import Flask, render_template_string
    
    application = Flask(__name__)
    
    @application.route('/')
    def home():
        return render_template_string('''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Controle de Estoque - Configuração OK</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; background: #f8f9fa; }
                .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .success { color: #28a745; border-left: 4px solid #28a745; padding-left: 20px; }
                .warning { color: #ffc107; border-left: 4px solid #ffc107; padding-left: 20px; }
                .info { background: #e7f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
                ul { padding-left: 25px; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1 class="success">🎉 Configuração WSGI Funcionando!</h1>
                
                <div class="info">
                    <h3>Status da Configuração:</h3>
                    <p><strong>✓ Virtual Host:</strong> Configurado corretamente</p>
                    <p><strong>✓ mod_wsgi:</strong> Funcionando</p>
                    <p><strong>✓ Python:</strong> {{ python_version }}</p>
                    <p><strong>✓ Caminho:</strong> /estoque</p>
                </div>
                
                <div class="warning">
                    <h3>⚠️ Aplicação Flask Principal Não Encontrada</h3>
                    <p>O arquivo <code>app.py</code> não foi encontrado ou não pode ser importado.</p>
                    <p><strong>Erro:</strong> {{ error }}</p>
                </div>
                
                <h3>Próximos Passos:</h3>
                <ol>
                    <li>Verificar se <code>app.py</code> existe em <code>/var/www/controle_estoque_db/</code></li>
                    <li>Instalar dependências Python: <code>pip install flask pandas openpyxl</code></li>
                    <li>Verificar permissões dos arquivos</li>
                    <li>Recarregar httpd após correções</li>
                </ol>
                
                <p><em>A configuração básica do httpd + mod_wsgi está funcionando. Agora precisa apenas configurar a aplicação Flask.</em></p>
            </div>
        </body>
        </html>
        ''', python_version=sys.version, error=str(e))
    
    # Aplicar middleware
    application = ReverseProxied(application, script_name='/estoque')

if __name__ == "__main__":
    application.run()
EOL

# 7. Ajustar permissões
echo -e "\n${YELLOW}7. Ajustando permissões...${NC}"
chown -R http:http /var/www/controle_estoque_db
chmod -R 755 /var/www/controle_estoque_db
chmod +x /var/www/controle_estoque_db/wsgi.py

# 8. Testar configuração
echo -e "\n${YELLOW}8. Testando configuração...${NC}"
httpd -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Configuração válida${NC}"
else
    echo -e "${RED}✗ Erro na configuração${NC}"
    echo "Restaurando backup..."
    cp "$VHOST_FILE.backup."* "$VHOST_FILE"
    exit 1
fi

# 9. Reiniciar httpd
echo -e "\n${YELLOW}9. Reiniciando httpd...${NC}"
systemctl restart httpd

# 10. Aguardar e testar
echo -e "\n${YELLOW}10. Aguardando inicialização (10 segundos)...${NC}"
sleep 10

# 11. Teste final
echo -e "\n${YELLOW}11. Teste final:${NC}"
echo "Status HTTP:"
curl -s -I http://localhost/estoque/ | head -2

echo -e "\n${GREEN}=== CORREÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}Teste no navegador:${NC} http://localhost/estoque/"
echo -e "${YELLOW}Logs de erro:${NC} tail -f /var/log/httpd/error_log"

echo -e "\n${YELLOW}Arquivos de backup criados:${NC}"
ls -la /etc/httpd/conf/extra/httpd-vhosts.conf.backup.*