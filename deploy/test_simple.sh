#!/bin/bash
# Configuração super simples para httpd

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CONFIGURAÇÃO SIMPLES HTTPD ===${NC}"

APP_DIR="/var/www/controle_estoque_db"
CONF_FILE="/etc/httpd/conf.d/estoque.conf"

# Detectar usuário httpd
HTTPD_USER=$(ps aux | grep httpd | grep -v root | head -1 | awk '{print $1}')
if [ -z "$HTTPD_USER" ]; then
    HTTPD_USER="nobody"
fi

echo "Usuário httpd: $HTTPD_USER"

# 1. Remover configuração antiga
rm -f /etc/httpd/conf.d/controle-estoque.conf

# 2. Criar configuração super simples
echo -e "${YELLOW}Criando configuração simples...${NC}"
cat > "$CONF_FILE" << EOL
# Configuração simples para /estoque

# WSGI básico
WSGIScriptAlias /estoque /var/www/controle_estoque_db/wsgi.py

# Diretório básico
<Directory /var/www/controle_estoque_db>
    Require all granted
</Directory>

# Arquivos estáticos básicos  
Alias /estoque/static /var/www/controle_estoque_db/static
<Directory /var/www/controle_estoque_db/static>
    Require all granted
</Directory>
EOL

# 3. Criar wsgi.py super simples para teste
echo -e "${YELLOW}Criando wsgi.py de teste...${NC}"
cat > "$APP_DIR/wsgi.py" << 'EOL'
#!/usr/bin/env python3

def application(environ, start_response):
    status = '200 OK'
    headers = [('Content-type', 'text/html')]
    start_response(status, headers)
    
    html = """
    <html>
    <head><title>Controle de Estoque - Teste</title></head>
    <body>
        <h1>🎉 Funciona!</h1>
        <p>A aplicação está respondendo em <strong>/estoque</strong></p>
        <p>Configuração WSGI básica funcionando!</p>
        <hr>
        <p>Próximo passo: configurar a aplicação Flask completa</p>
    </body>
    </html>
    """
    
    return [html.encode('utf-8')]
EOL

# 4. Ajustar permissões
echo -e "${YELLOW}Ajustando permissões...${NC}"
chown -R $HTTPD_USER:$HTTPD_USER "$APP_DIR" 2>/dev/null || chown -R nobody:nobody "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod +x "$APP_DIR/wsgi.py"

# 5. Testar configuração
echo -e "${YELLOW}Testando configuração...${NC}"
httpd -t

# 6. Reiniciar httpd
echo -e "${YELLOW}Reiniciando httpd...${NC}"
systemctl restart httpd

# 7. Aguardar e testar
echo -e "${YELLOW}Aguardando httpd inicializar...${NC}"
sleep 3

echo -e "${YELLOW}Testando acesso...${NC}"
curl -s http://localhost/estoque/ | head -5

echo -e "\n${GREEN}=== TESTE CONCLUÍDO ===${NC}"
echo -e "${YELLOW}Agora teste no navegador:${NC} http://localhost/estoque/"
echo ""
echo -e "${YELLOW}Se funcionar, podemos configurar a aplicação Flask completa!${NC}"