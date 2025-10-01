#!/bin/bash
# Script simplificado para corrigir configuração sem módulos opcionais

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CORREÇÃO SIMPLIFICADA ===${NC}"

VHOST_FILE="/etc/httpd/conf/extra/httpd-vhosts.conf"

# 1. Fazer backup correto
echo -e "${YELLOW}1. Fazendo backup...${NC}"
BACKUP_FILE="${VHOST_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$VHOST_FILE" "$BACKUP_FILE"
echo "Backup criado: $BACKUP_FILE"

# 2. Criar configuração limpa e simples
echo -e "\n${YELLOW}2. Criando configuração limpa...${NC}"

cat > "$VHOST_FILE" << 'EOL'
# Virtual Hosts

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

    # CONTROLE DE ESTOQUE - Configuração simples
    WSGIDaemonProcess controle_estoque python-path=/var/www/controle_estoque_db python-home=/var/www/controle_estoque_db/venv
    WSGIProcessGroup controle_estoque
    WSGIScriptAlias /estoque /var/www/controle_estoque_db/wsgi.py

    <Directory /var/www/controle_estoque_db>
        WSGIApplicationGroup %{GLOBAL}
        Require all granted
        Options -Indexes
    </Directory>

    # Arquivos estáticos simples
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

</VirtualHost>
EOL

# 3. Limpar configurações conflitantes
echo -e "\n${YELLOW}3. Limpando arquivos conflitantes...${NC}"
rm -f /etc/httpd/conf.d/*estoque*.conf

# 4. Criar wsgi.py simples para teste
echo -e "\n${YELLOW}4. Criando wsgi.py de teste...${NC}"
cat > /var/www/controle_estoque_db/wsgi.py << 'EOL'
#!/usr/bin/env python3

def application(environ, start_response):
    status = '200 OK'
    headers = [('Content-type', 'text/html; charset=utf-8')]
    start_response(status, headers)
    
    html = """<!DOCTYPE html>
<html>
<head>
    <title>Controle de Estoque - Teste OK</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f0f8ff; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
        .success { color: #28a745; }
        .info { background: #e7f3ff; padding: 15px; border-radius: 5px; margin: 15px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✅ WSGI Funcionando!</h1>
        <div class="info">
            <p><strong>Caminho:</strong> /estoque</p>
            <p><strong>Status:</strong> Configuração básica OK</p>
            <p><strong>Servidor:</strong> httpd + mod_wsgi</p>
        </div>
        <h3>Próximos passos:</h3>
        <ol>
            <li>Copiar arquivos da aplicação Flask</li>
            <li>Instalar dependências Python</li>
            <li>Configurar ambiente virtual</li>
        </ol>
        <p><em>A configuração WSGI básica está funcionando corretamente!</em></p>
    </div>
</body>
</html>"""
    
    return [html.encode('utf-8')]
EOL

# 5. Ajustar permissões
echo -e "\n${YELLOW}5. Ajustando permissões...${NC}"
chown -R http:http /var/www/controle_estoque_db
chmod -R 755 /var/www/controle_estoque_db
chmod +x /var/www/controle_estoque_db/wsgi.py

# 6. Testar configuração
echo -e "\n${YELLOW}6. Testando configuração...${NC}"
httpd -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Configuração válida${NC}"
    
    # 7. Reiniciar httpd
    echo -e "\n${YELLOW}7. Reiniciando httpd...${NC}"
    systemctl restart httpd
    
    # 8. Aguardar e testar
    echo -e "\n${YELLOW}8. Aguardando (5 segundos)...${NC}"
    sleep 5
    
    # 9. Teste HTTP
    echo -e "\n${YELLOW}9. Testando acesso:${NC}"
    HTTP_RESPONSE=$(curl -s -w "%{http_code}" http://localhost/estoque/ -o /tmp/test_response.html)
    
    if [ "$HTTP_RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ Sucesso! HTTP $HTTP_RESPONSE${NC}"
        echo "Conteúdo (primeiras linhas):"
        head -5 /tmp/test_response.html
    else
        echo -e "${RED}✗ Erro HTTP: $HTTP_RESPONSE${NC}"
        echo "Verificando logs..."
        tail -5 /var/log/httpd/error_log
    fi
    
else
    echo -e "${RED}✗ Erro na configuração${NC}"
    echo "Restaurando backup..."
    cp "$BACKUP_FILE" "$VHOST_FILE"
    exit 1
fi

echo -e "\n${GREEN}=== TESTE CONCLUÍDO ===${NC}"
echo -e "${YELLOW}URL para teste:${NC} http://localhost/estoque/"
echo -e "${YELLOW}Backup salvo em:${NC} $BACKUP_FILE"