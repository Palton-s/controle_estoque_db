#!/bin/bash
# Script simplificado para configurar aplicação em servidor httpd existente
# Controle de Estoque - Deploy em servidor httpd existente

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== CONFIGURAÇÃO PARA SERVIDOR HTTPD EXISTENTE ===${NC}"

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script deve ser executado como root (sudo)${NC}" 
   exit 1
fi

# Variáveis de configuração
APP_DIR="/var/www/controle_estoque_db"
APP_USER="apache"  # Usuário padrão do httpd
BASE_URL="localhost/estoque"  # Rodará em localhost/estoque

echo -e "${YELLOW}Configurações para httpd:${NC}"
echo "Diretório da aplicação: $APP_DIR"
echo "Usuário da aplicação: $APP_USER"
echo "URL da aplicação: http://$BASE_URL"
echo ""

# 1. Verificar se httpd está rodando
echo -e "${GREEN}1. Verificando status do httpd...${NC}"
if systemctl is-active --quiet httpd; then
    echo -e "${GREEN}✓ httpd está rodando${NC}"
else
    echo -e "${RED}✗ httpd não está rodando${NC}"
    echo "Inicie o httpd antes de continuar: systemctl start httpd"
    exit 1
fi

# 2. Instalar dependências Python (sem tocar no Apache)
echo -e "${GREEN}2. Instalando dependências Python...${NC}"
yum install -y python3 python3-pip python3-devel python3-mod_wsgi || \
dnf install -y python3 python3-pip python3-devel python3-mod_wsgi || \
echo "Verifique se python3-mod_wsgi está instalado"

# 3. Verificar mod_wsgi
echo -e "${GREEN}3. Verificando mod_wsgi...${NC}"
if httpd -M 2>/dev/null | grep -q wsgi; then
    echo -e "${GREEN}✓ mod_wsgi já está carregado${NC}"
else
    echo -e "${YELLOW}! mod_wsgi não encontrado, adicionando configuração...${NC}"
    
    # Tentar encontrar mod_wsgi
    WSGI_SO=$(find /usr/lib64/httpd/modules /usr/lib/httpd/modules -name "*wsgi*" 2>/dev/null | head -1)
    
    if [ -n "$WSGI_SO" ]; then
        echo "LoadModule wsgi_module $WSGI_SO" > /etc/httpd/conf.modules.d/10-wsgi.conf
        echo -e "${GREEN}✓ mod_wsgi configurado${NC}"
    else
        echo -e "${RED}✗ mod_wsgi não encontrado. Instale manualmente: yum install python3-mod_wsgi${NC}"
        exit 1
    fi
fi

# 4. Criar diretório da aplicação
echo -e "${GREEN}4. Criando estrutura de diretórios...${NC}"
mkdir -p $APP_DIR
cd $APP_DIR

# Criar diretórios necessários
mkdir -p logs relatorios temp static templates utils scripts
chown -R $APP_USER:$APP_USER $APP_DIR
chmod -R 755 $APP_DIR
chmod -R 775 logs relatorios temp

# 5. Criar ambiente virtual Python
echo -e "${GREEN}5. Criando ambiente virtual Python...${NC}"
python3 -m venv venv
source venv/bin/activate

# 6. Instalar dependências Python
echo -e "${GREEN}6. Instalando dependências Python...${NC}"
pip install --upgrade pip

# Criar requirements.txt básico
cat > requirements.txt << EOL
Flask==3.1.1
Werkzeug==3.1.3
Jinja2==3.1.6
pandas==2.3.1
openpyxl==3.1.5
numpy==2.3.2
python-dateutil==2.9.0.post0
pytz==2025.2
EOL

pip install -r requirements.txt

# 7. Criar configuração do Virtual Host
echo -e "${GREEN}7. Criando configuração do Virtual Host...${NC}"

# Detectar diretório de configuração do httpd
if [ -d "/etc/httpd/conf.d" ]; then
    CONF_DIR="/etc/httpd/conf.d"
elif [ -d "/etc/apache2/sites-available" ]; then
    CONF_DIR="/etc/apache2/sites-available"
else
    CONF_DIR="/etc/httpd/conf.d"
    mkdir -p $CONF_DIR
fi

cat > $CONF_DIR/controle-estoque.conf << EOL
# Configuração para Controle de Estoque em localhost/estoque
# Usando servidor httpd existente

# Configuração WSGI para aplicação em subdiretório
WSGIDaemonProcess controle_estoque python-path=$APP_DIR python-home=$APP_DIR/venv
WSGIScriptAlias /estoque $APP_DIR/wsgi.py
# Configuração de diretórios para aplicação em subdiretório
<Directory $APP_DIR>
    WSGIProcessGroup controle_estoque
    WSGIApplicationGroup %{GLOBAL}
    Require all granted
    Options -Indexes
</Directory>

# Servir arquivos estáticos em /estoque/static
Alias /estoque/static $APP_DIR/static
<Directory $APP_DIR/static>
    Require all granted
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
    Options -Indexes
</Directory>

# Alias para downloads de relatórios em /estoque/relatorios
Alias /estoque/relatorios $APP_DIR/relatorios
<Directory $APP_DIR/relatorios>
    Require all granted
    Options -Indexes
</Directory>
# Configurações específicas para a aplicação /estoque
<Location /estoque>
    # Headers de segurança
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
</Location>

# Compressão gzip para aplicação /estoque
<Location /estoque>
    SetOutputFilter DEFLATE
    SetEnvIfNoCase Request_URI \.(?:gif|jpe?g|png)$ no-gzip dont-vary
    SetEnvIfNoCase Request_URI \.(?:exe|t?gz|zip|bz2|sit|rar)$ no-gzip dont-vary
</Location>

# Cache para arquivos estáticos da aplicação
<LocationMatch "^/estoque/static/.*\.(css|js|png|jpg|jpeg|gif|ico|svg)$">
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
    Header append Cache-Control "public"
</LocationMatch>

# Para HTTPS, a mesma configuração funciona automaticamente
# pois usa caminhos relativos (WSGIScriptAlias /estoque)
# Não precisa de configuração adicional para SSL
EOL

# 8. Configurar logrotate
echo -e "${GREEN}8. Configurando rotação de logs...${NC}"
cat > /etc/logrotate.d/controle-estoque << EOL
/var/www/controle_estoque_db/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 $APP_USER $APP_USER
    postrotate
        /bin/systemctl reload httpd > /dev/null 2>&1 || true
    endscript
}

/var/log/httpd/controle_estoque*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/systemctl reload httpd > /dev/null 2>&1 || true
    endscript
}
EOL

# 9. Ajustar permissões finais
echo -e "${GREEN}9. Ajustando permissões finais...${NC}"
chown -R $APP_USER:$APP_USER $APP_DIR
chmod -R 755 $APP_DIR
chmod -R 775 $APP_DIR/logs $APP_DIR/relatorios $APP_DIR/temp

# 10. Testar configuração do httpd
echo -e "${GREEN}10. Testando configuração do httpd...${NC}"
if httpd -t; then
    echo -e "${GREEN}✓ Configuração do httpd OK${NC}"
else
    echo -e "${RED}✗ Erro na configuração do httpd${NC}"
    echo "Verifique o arquivo $CONF_DIR/controle-estoque.conf"
    exit 1
fi

# 11. Recarregar httpd (sem reiniciar para não afetar outras aplicações)
echo -e "${GREEN}11. Recarregando configuração do httpd...${NC}"
systemctl reload httpd

echo -e "${GREEN}=== CONFIGURAÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}Próximos passos:${NC}"
echo "1. Copie os arquivos da aplicação para $APP_DIR"
echo "2. Crie o arquivo wsgi.py no diretório $APP_DIR"
echo "3. Teste a aplicação em http://$BASE_URL"
echo ""
echo -e "${YELLOW}Arquivos de configuração criados:${NC}"
echo "- Virtual Host: $CONF_DIR/controle-estoque.conf"
echo "- Logrotate: /etc/logrotate.d/controle-estoque"
echo ""
echo -e "${YELLOW}Comandos úteis:${NC}"
echo "- Logs httpd: tail -f /var/log/httpd/controle_estoque_error.log"
echo "- Logs app: tail -f $APP_DIR/logs/app.log"
echo "- Recarregar httpd: systemctl reload httpd"
echo "- Status httpd: systemctl status httpd"
echo "- Testar config: httpd -t"
echo ""
echo -e "${GREEN}Configuração concluída! httpd não foi reiniciado para não afetar outras aplicações.${NC}"