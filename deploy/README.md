# Guia Completo de Deploy - Controle de Estoque no Apache/Linux

## Visão Geral
Este guia fornece instruções completas para fazer o deploy da aplicação Flask "Controle de Estoque" em um servidor Linux com Apache2 e mod_wsgi.

## Pré-requisitos
- Servidor Linux (Ubuntu 20.04+ ou CentOS 8+ recomendado)
- Acesso root (sudo) ao servidor
- Domínio configurado (opcional, pode usar IP)
- Mínimo 2GB RAM, 20GB disco

## Estrutura de Arquivos Criados

```
deploy/
├── install_apache.sh     # Script de instalação completa
├── deploy.sh            # Script de deploy da aplicação
└── README.md           # Este arquivo

apache-config/
└── controle-estoque.conf # Configuração do Virtual Host

wsgi.py                  # Interface WSGI para produção
```

## Passo a Passo

### 1. Preparação do Servidor

```bash
# Conectar ao servidor via SSH
ssh usuario@seu-servidor.com

# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar git (se necessário)
sudo apt install git -y
```

### 2. Upload dos Arquivos

Opção A - Via Git:
```bash
# Clonar o repositório
git clone https://github.com/usuario/controle_estoque_db.git
cd controle_estoque_db
```

Opção B - Via SCP/SFTP:
```bash
# Do seu computador local
scp -r /caminho/para/aplicacao usuario@servidor:/tmp/controle_estoque
```

### 3. Instalação Automática

```bash
# Tornar executável
chmod +x deploy/install_apache.sh

# Executar instalação (como root)
sudo ./deploy/install_apache.sh
```

O script irá:
- Instalar Apache2 e mod_wsgi
- Configurar Python e ambiente virtual
- Criar estrutura de diretórios
- Configurar Virtual Host
- Configurar segurança básica
- Configurar logs e monitoramento

### 4. Personalização

Editar configurações conforme necessário:

```bash
# Editar domínio no Virtual Host
sudo nano /etc/apache2/sites-available/controle-estoque.conf

# Alterar ServerName para seu domínio
ServerName seu-dominio.com.br
ServerAlias www.seu-dominio.com.br
```

### 5. Deploy da Aplicação

```bash
# Na pasta da aplicação
chmod +x deploy/deploy.sh
sudo ./deploy/deploy.sh
```

### 6. Verificação

```bash
# Verificar status do Apache
sudo systemctl status apache2

# Verificar logs
sudo tail -f /var/log/apache2/controle_estoque_error.log

# Testar aplicação
curl -I http://seu-dominio.com.br
```

## Configuração Manual (Alternativa)

Se preferir configurar manualmente:

### 1. Instalar Dependências

```bash
sudo apt update
sudo apt install apache2 libapache2-mod-wsgi-py3 python3 python3-pip python3-venv
```

### 2. Habilitar Módulos

```bash
sudo a2enmod wsgi
sudo a2enmod rewrite
sudo a2enmod headers
```

### 3. Configurar Aplicação

```bash
# Criar diretório
sudo mkdir -p /var/www/controle_estoque_db
cd /var/www/controle_estoque_db

# Copiar arquivos
sudo cp -r /caminho/origem/* .

# Criar ambiente virtual
sudo python3 -m venv venv
sudo venv/bin/pip install -r requirements.txt
```

### 4. Configurar Apache

```bash
# Copiar configuração
sudo cp apache-config/controle-estoque.conf /etc/apache2/sites-available/

# Habilitar site
sudo a2ensite controle-estoque
sudo a2dissite 000-default

# Reiniciar Apache
sudo systemctl restart apache2
```

## Estrutura Final no Servidor

```
/var/www/controle_estoque_db/
├── app.py                 # Aplicação principal
├── wsgi.py               # Interface WSGI
├── requirements.txt      # Dependências Python
├── venv/                 # Ambiente virtual Python
├── static/               # Arquivos estáticos (CSS, JS)
├── templates/            # Templates HTML
├── utils/                # Módulos Python da aplicação
├── logs/                 # Logs da aplicação
├── relatorios/          # Relatórios gerados
├── temp/                # Arquivos temporários
└── relatorios/          # Base de dados SQLite
```

## Configurações de Segurança

### Firewall
```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

### SSL/HTTPS (Recomendado)

```bash
# Instalar Certbot
sudo apt install certbot python3-certbot-apache

# Obter certificado
sudo certbot --apache -d seu-dominio.com.br

# Renovação automática
sudo crontab -e
# Adicionar: 0 12 * * * /usr/bin/certbot renew --quiet
```

## Monitoramento e Manutenção

### Logs Importantes
- Apache Error: `/var/log/apache2/controle_estoque_error.log`
- Apache Access: `/var/log/apache2/controle_estoque_access.log`
- App Logs: `/var/www/controle_estoque/logs/`

### Comandos Úteis

```bash
# Status dos serviços
sudo systemctl status apache2

# Restart Apache
sudo systemctl restart apache2

# Verificar configuração
sudo apache2ctl configtest

# Monitorar logs em tempo real
sudo tail -f /var/log/apache2/controle_estoque_error.log

# Verificar processos Python
ps aux | grep python

# Espaço em disco
df -h /var/www/controle_estoque_db
```

### Backup Automático

```bash
# Criar script de backup
sudo nano /usr/local/bin/backup_controle_estoque.sh

#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/controle_estoque_db"
APP_DIR="/var/www/controle_estoque_db"

mkdir -p $BACKUP_DIR
tar -czf "$BACKUP_DIR/backup_$DATE.tar.gz" -C "$APP_DIR" .
find $BACKUP_DIR -name "backup_*.tar.gz" -mtime +30 -delete

# Tornar executável
sudo chmod +x /usr/local/bin/backup_controle_estoque.sh

# Adicionar ao crontab
sudo crontab -e
# Backup diário às 2h: 0 2 * * * /usr/local/bin/backup_controle_estoque.sh
```

## Solução de Problemas

### Problema: Erro 500 Internal Server Error
```bash
# Verificar logs
sudo tail -f /var/log/apache2/controle_estoque_error.log

# Verificar permissões
sudo chown -R www-data:www-data /var/www/controle_estoque_db
sudo chmod -R 755 /var/www/controle_estoque_db
```

### Problema: Módulo Python não encontrado
```bash
# Ativar venv e reinstalar
cd /var/www/controle_estoque_db
sudo -u www-data venv/bin/pip install -r requirements.txt
```

### Problema: Banco de dados não acessível
```bash
# Verificar permissões do SQLite
sudo chown www-data:www-data /var/www/controle_estoque_db/relatorios/*.db
sudo chmod 664 /var/www/controle_estoque_db/relatorios/*.db
```

### Problema: Arquivos estáticos não carregam
```bash
# Verificar configuração do alias no Apache
# Verificar permissões da pasta static
sudo chown -R www-data:www-data /var/www/controle_estoque_db/static
```

## Performance e Otimização

### Configurar cache
```apache
# Adicionar ao Virtual Host
<LocationMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg)$">
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
    Header append Cache-Control "public"
</LocationMatch>
```

### Compressão gzip
```apache
<Location />
    SetOutputFilter DEFLATE
    SetEnvIfNoCase Request_URI \.(?:gif|jpe?g|png)$ no-gzip dont-vary
</Location>
```

## Contato e Suporte

Para dúvidas ou problemas:
1. Verifique os logs primeiro
2. Consulte este guia
3. Teste em ambiente local
4. Documente o problema encontrado

---

**Nota**: Sempre faça backup antes de aplicar mudanças em produção!