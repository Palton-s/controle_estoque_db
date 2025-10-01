#!/bin/bash
# Solução rápida: desabilitar Virtual Host conflitante

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== SOLUÇÃO RÁPIDA: DESABILITAR VHOST CONFLITANTE ===${NC}"

# 1. Backup da configuração atual
echo -e "${YELLOW}1. Fazendo backup da configuração...${NC}"
cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.backup.$(date +%Y%m%d_%H%M%S)

# 2. Desabilitar Include de vhosts
echo -e "${YELLOW}2. Desabilitando Virtual Host conflitante...${NC}"
sed -i 's/^Include.*httpd-vhosts.conf/#&/' /etc/httpd/conf/httpd.conf

# 3. Verificar se foi desabilitado
echo "Status do Include:"
grep "httpd-vhosts.conf" /etc/httpd/conf/httpd.conf

# 4. Criar nova configuração mais específica
echo -e "${YELLOW}3. Criando configuração específica...${NC}"
cat > /etc/httpd/conf.d/000-estoque.conf << 'EOL'
# Configuração prioritária para /estoque

# WSGI Configuration
WSGIScriptAlias /estoque /var/www/controle_estoque_db/wsgi.py

# Directory permissions
<Directory /var/www/controle_estoque_db>
    Require all granted
    AllowOverride None
    Options -Indexes
</Directory>

# Static files
Alias /estoque/static /var/www/controle_estoque_db/static
<Directory /var/www/controle_estoque_db/static>
    Require all granted
    Options -Indexes
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
</Directory>

# Reports
Alias /estoque/relatorios /var/www/controle_estoque_db/relatorios  
<Directory /var/www/controle_estoque_db/relatorios>
    Require all granted
    Options -Indexes
</Directory>
EOL

# 5. Remover configurações antigas
rm -f /etc/httpd/conf.d/estoque.conf
rm -f /etc/httpd/conf.d/controle-estoque.conf

# 6. Criar wsgi.py simples para teste
echo -e "${YELLOW}4. Criando wsgi.py de teste...${NC}"
cat > /var/www/controle_estoque_db/wsgi.py << 'EOL'
#!/usr/bin/env python3

def application(environ, start_response):
    status = '200 OK'
    headers = [('Content-type', 'text/html; charset=utf-8')]
    start_response(status, headers)
    
    path = environ.get('PATH_INFO', '')
    
    html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Controle de Estoque - Funcionando!</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        .success {{ color: #28a745; }}
        .info {{ background: #f8f9fa; padding: 20px; border-radius: 5px; }}
    </style>
</head>
<body>
    <h1 class="success">🎉 FUNCIONOU!</h1>
    <div class="info">
        <h3>Informações da Requisição:</h3>
        <p><strong>Caminho:</strong> {path}</p>
        <p><strong>URL completa:</strong> http://localhost/estoque{path}</p>
        <p><strong>Status:</strong> Configuração WSGI funcionando!</p>
    </div>
    <hr>
    <h3>Próximos passos:</h3>
    <ol>
        <li>Configurar ambiente virtual Python</li>
        <li>Instalar Flask e dependências</li>
        <li>Configurar aplicação Flask completa</li>
    </ol>
    <p><em>Configuração básica do httpd + mod_wsgi está funcionando corretamente!</em></p>
</body>
</html>"""
    
    return [html.encode('utf-8')]
EOL

# 7. Ajustar permissões
echo -e "${YELLOW}5. Ajustando permissões...${NC}"
chown -R http:http /var/www/controle_estoque_db
chmod -R 755 /var/www/controle_estoque_db
chmod +x /var/www/controle_estoque_db/wsgi.py

# 8. Testar configuração
echo -e "${YELLOW}6. Testando configuração...${NC}"
httpd -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Configuração válida${NC}"
else
    echo -e "${RED}✗ Erro na configuração - restaurando backup${NC}"
    cp /etc/httpd/conf/httpd.conf.backup.* /etc/httpd/conf/httpd.conf
    exit 1
fi

# 9. Reiniciar httpd
echo -e "${YELLOW}7. Reiniciando httpd...${NC}"
systemctl restart httpd

# 10. Aguardar e testar
echo -e "${YELLOW}8. Aguardando inicialização...${NC}"
sleep 5

# 11. Teste final
echo -e "${YELLOW}9. Teste final:${NC}"
echo "Headers HTTP:"
curl -s -I http://localhost/estoque/ | head -3

echo ""
echo "Conteúdo (primeiras linhas):"
curl -s http://localhost/estoque/ | head -10

echo ""
echo -e "${GREEN}=== CONFIGURAÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}Teste no navegador:${NC} http://localhost/estoque/"
echo -e "${YELLOW}Se aparecer '🎉 FUNCIONOU!', a configuração está correta!${NC}"