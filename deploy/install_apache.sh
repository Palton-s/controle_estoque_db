#!/bin/bash
# Script de instalação e configuração para Deploy no Apache
# Controle de Estoque - Linux Deploy

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== INSTALAÇÃO DO CONTROLE DE ESTOQUE NO APACHE ===${NC}"

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script deve ser executado como root (sudo)${NC}" 
   exit 1
fi

# Detectar distribuição Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    DISTRO="unknown"
fi

# Variáveis de configuração
APP_DIR="/var/www/controle_estoque_db"
DOMAIN="seu-dominio.com.br"  # ALTERE AQUI
PYTHON_VERSION="3.9"  # Ajuste conforme necessário

# Configurar variáveis baseadas na distribuição
case $DISTRO in
    "ubuntu"|"debian")
        PKG_MANAGER="apt"
        APACHE_PKG="apache2"
        APACHE_USER="www-data"
        APACHE_SERVICE="apache2"
        WSGI_PKG="libapache2-mod-wsgi-py3"
        APACHE_ENABLE_CMD="a2enmod"
        APACHE_SITE_CMD="a2ensite"
        ;;
    "centos"|"rhel"|"fedora")
        PKG_MANAGER="yum"
        APACHE_PKG="httpd"
        APACHE_USER="apache"
        APACHE_SERVICE="httpd"
        WSGI_PKG="python3-mod_wsgi"
        APACHE_ENABLE_CMD="httpd_enable_mod"
        APACHE_SITE_CMD="httpd_enable_site"
        ;;
    *)
        echo -e "${YELLOW}Distribuição desconhecida, usando padrões Ubuntu/Debian${NC}"
        PKG_MANAGER="apt"
        APACHE_PKG="apache2"
        APACHE_USER="www-data"
        APACHE_SERVICE="apache2"
        WSGI_PKG="libapache2-mod-wsgi-py3"
        APACHE_ENABLE_CMD="a2enmod"
        APACHE_SITE_CMD="a2ensite"
        ;;
esac

APP_USER=$APACHE_USER

echo -e "${YELLOW}Configurações detectadas:${NC}"
echo "Distribuição: $DISTRO"
echo "Diretório da aplicação: $APP_DIR"
echo "Usuário da aplicação: $APP_USER"
echo "Domínio: $DOMAIN"
echo "Serviço Apache: $APACHE_SERVICE"
echo ""

# 1. Atualizar sistema
echo -e "${GREEN}1. Atualizando sistema...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update && apt upgrade -y
elif [ "$PKG_MANAGER" = "yum" ]; then
    yum update -y
fi

# 2. Instalar dependências do sistema
echo -e "${GREEN}2. Instalando dependências do sistema...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    apt install -y \
        $APACHE_PKG \
        $WSGI_PKG \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        git \
        curl \
        wget \
        unzip \
        sqlite3 \
        libsqlite3-dev \
        supervisor
elif [ "$PKG_MANAGER" = "yum" ]; then
    yum install -y \
        $APACHE_PKG \
        $WSGI_PKG \
        python3 \
        python3-pip \
        python3-devel \
        gcc \
        git \
        curl \
        wget \
        unzip \
        sqlite \
        sqlite-devel \
        supervisor
fi

# 3. Habilitar módulos do Apache
echo -e "${GREEN}3. Habilitando módulos do Apache...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    # Ubuntu/Debian
    a2enmod wsgi 2>/dev/null || echo "Módulo wsgi já habilitado ou não disponível"
    a2enmod rewrite 2>/dev/null || echo "Módulo rewrite já habilitado ou não disponível"
    a2enmod headers 2>/dev/null || echo "Módulo headers já habilitado ou não disponível"
    a2enmod expires 2>/dev/null || echo "Módulo expires já habilitado ou não disponível"
    a2enmod deflate 2>/dev/null || echo "Módulo deflate já habilitado ou não disponível"
    a2enmod ssl 2>/dev/null || echo "Módulo ssl já habilitado ou não disponível"
elif [ "$PKG_MANAGER" = "yum" ]; then
    # CentOS/RHEL/Fedora - módulos já incluídos normalmente
    echo "Módulos do Apache (CentOS/RHEL) - verificando configuração..."
    if [ -f /etc/httpd/conf.modules.d/00-base.conf ]; then
        echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/httpd/conf.modules.d/00-base.conf 2>/dev/null || true
        echo "LoadModule headers_module modules/mod_headers.so" >> /etc/httpd/conf.modules.d/00-base.conf 2>/dev/null || true
        echo "LoadModule expires_module modules/mod_expires.so" >> /etc/httpd/conf.modules.d/00-base.conf 2>/dev/null || true
        echo "LoadModule deflate_module modules/mod_deflate.so" >> /etc/httpd/conf.modules.d/00-base.conf 2>/dev/null || true
    fi
fi

# 4. Criar diretório da aplicação
echo -e "${GREEN}4. Criando estrutura de diretórios...${NC}"
mkdir -p $APP_DIR
cd $APP_DIR

# 5. Configurar propriedades dos diretórios
echo -e "${GREEN}5. Configurando permissões...${NC}"
chown -R $APP_USER:$APP_USER $APP_DIR
chmod -R 755 $APP_DIR

# Criar diretórios necessários
mkdir -p logs relatorios temp static templates utils scripts
chown -R $APP_USER:$APP_USER logs relatorios temp
chmod -R 775 logs relatorios temp

# 6. Criar ambiente virtual Python
echo -e "${GREEN}6. Criando ambiente virtual Python...${NC}"
python3 -m venv venv
source venv/bin/activate

# 7. Instalar dependências Python
echo -e "${GREEN}7. Instalando dependências Python...${NC}"
pip install --upgrade pip

# Criar requirements.txt otimizado para produção
cat > requirements.txt << EOL
Flask==3.1.1
Werkzeug==3.1.3
Jinja2==3.1.6
click==8.2.1
itsdangerous==2.2.0
MarkupSafe==3.0.2
blinker==1.9.0
pandas==2.3.1
openpyxl==3.1.5
numpy==2.3.2
python-dateutil==2.9.0.post0
pytz==2025.2
six==1.17.0
et_xmlfile==2.0.0
gunicorn==21.2.0
EOL

pip install -r requirements.txt

# 8. Criar configuração de produção para Flask
echo -e "${GREEN}8. Criando configuração de produção...${NC}"
cat > config.py << EOL
import os

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or '$(openssl rand -hex 32)'
    
class ProductionConfig(Config):
    DEBUG = False
    TESTING = False
    
class DevelopmentConfig(Config):
    DEBUG = True
    TESTING = False

config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': ProductionConfig
}
EOL

# 9. Criar script de inicialização
echo -e "${GREEN}9. Criando scripts de controle...${NC}"
cat > start_app.sh << 'EOL'
#!/bin/bash
cd /var/www/controle_estoque_db
source venv/bin/activate
export FLASK_APP=app.py
export FLASK_ENV=production
exec gunicorn --bind 127.0.0.1:5000 --workers 3 --timeout 120 wsgi:application
EOL

chmod +x start_app.sh

# 10. Configurar Supervisor (para gerenciar o processo)
echo -e "${GREEN}10. Configurando Supervisor...${NC}"
cat > /etc/supervisor/conf.d/controle-estoque.conf << EOL
[program:controle-estoque]
command=/var/www/controle_estoque_db/start_app.sh
directory=/var/www/controle_estoque_db
user=www-data
autostart=true
autorestart=true
stdout_logfile=/var/www/controle_estoque_db/logs/supervisor.log
stderr_logfile=/var/www/controle_estoque_db/logs/supervisor_error.log
environment=PATH="/var/www/controle_estoque_db/venv/bin"
EOL

# 11. Criar configuração do Apache
echo -e "${GREEN}11. Configurando Apache Virtual Host...${NC}"
cat > /etc/apache2/sites-available/controle-estoque.conf << EOL
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    
    DocumentRoot $APP_DIR
    
    WSGIDaemonProcess controle_estoque python-path=$APP_DIR python-home=$APP_DIR/venv
    WSGIProcessGroup controle_estoque
    WSGIScriptAlias / $APP_DIR/wsgi.py
    WSGIApplicationGroup %{GLOBAL}
    
    <Directory $APP_DIR>
        WSGIApplicationGroup %{GLOBAL}
        Require all granted
    </Directory>
    
    Alias /static $APP_DIR/static
    <Directory $APP_DIR/static>
        Require all granted
        ExpiresActive On
        ExpiresDefault "access plus 1 month"
    </Directory>
    
    Alias /relatorios $APP_DIR/relatorios
    <Directory $APP_DIR/relatorios>
        Require all granted
        Options -Indexes
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/controle_estoque_error.log
    CustomLog \${APACHE_LOG_DIR}/controle_estoque_access.log combined
    LogLevel info
    
    # Headers de segurança
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    
    # Compressão
    <Location />
        SetOutputFilter DEFLATE
    </Location>
</VirtualHost>
EOL

# 12. Habilitar site e desabilitar default
echo -e "${GREEN}12. Habilitando site...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    # Ubuntu/Debian
    a2dissite 000-default 2>/dev/null || echo "Site default já desabilitado"
    a2ensite controle-estoque
elif [ "$PKG_MANAGER" = "yum" ]; then
    # CentOS/RHEL - não usa a2ensite, arquivo já está no lugar certo
    echo "Configuração do site (CentOS/RHEL) já aplicada"
fi

# 13. Configurar firewall básico
echo -e "${GREEN}13. Configurando firewall...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 14. Configurar logrotate
echo -e "${GREEN}14. Configurando rotação de logs...${NC}"
cat > /etc/logrotate.d/controle-estoque << EOL
/var/www/controle_estoque/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        /bin/systemctl reload apache2 > /dev/null 2>&1 || true
    endscript
}
EOL

# 15. Ajustar permissões finais
echo -e "${GREEN}15. Ajustando permissões finais...${NC}"
chown -R $APP_USER:$APP_USER $APP_DIR
chmod -R 755 $APP_DIR
chmod -R 775 $APP_DIR/logs $APP_DIR/relatorios $APP_DIR/temp
chmod +x $APP_DIR/wsgi.py

# 16. Reiniciar serviços
echo -e "${GREEN}16. Reiniciando serviços...${NC}"
systemctl restart supervisor
systemctl reload apache2
systemctl enable supervisor
systemctl enable apache2

# Verificar status
echo -e "${GREEN}=== STATUS DOS SERVIÇOS ===${NC}"
systemctl status apache2 --no-pager -l
echo ""
systemctl status supervisor --no-pager -l

echo -e "${GREEN}=== INSTALAÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}Próximos passos:${NC}"
echo "1. Copie os arquivos da aplicação para $APP_DIR"
echo "2. Configure o domínio em /etc/apache2/sites-available/controle-estoque.conf"
echo "3. Configure SSL/HTTPS se necessário"
echo "4. Teste a aplicação em http://$DOMAIN"
echo ""
echo -e "${YELLOW}Comandos úteis:${NC}"
echo "- Logs Apache: tail -f /var/log/apache2/controle_estoque_error.log"
echo "- Logs App: tail -f $APP_DIR/logs/app.log"
echo "- Reiniciar: systemctl restart apache2"
echo "- Status: systemctl status apache2"
echo ""
echo -e "${GREEN}Configuração concluída com sucesso!${NC}"