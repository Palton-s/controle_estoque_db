# Guia de Deploy para Servidor httpd Existente

## Visão Geral
Este guia é específico para fazer o deploy da aplicação Flask "Controle de Estoque" em um servidor Linux que já tem httpd (Apache HTTP Server) rodando com outras aplicações.

## Diferenças para servidor httpd existente

### ⚠️ **Cuidados Importantes**
- **NÃO reinicia o httpd** (apenas reload para não afetar outras aplicações)
- **NÃO altera configurações globais** do httpd
- **USA configuração isolada** no Virtual Host
- **Compatível com CentOS/RHEL/Fedora**

## Pré-requisitos Verificados
- ✅ Servidor Linux com httpd instalado e rodando
- ✅ Outras aplicações já funcionando no httpd
- ✅ Acesso root (sudo) ao servidor
- ✅ Python3 disponível

## Arquivos Específicos para httpd

### 📁 Estrutura de arquivos para httpd:
```
deploy/
├── setup_httpd_existing.sh    # Script específico para httpd existente
├── deploy.sh                 # Deploy compatível com httpd
├── check_status.sh           # Status compatível com httpd
└── README_httpd.md          # Este arquivo
```

## Instalação Rápida

### 1. Upload e Execução
```bash
# No servidor Linux com httpd
cd /tmp
# (assumindo que você já fez upload dos arquivos)

# Executar configuração específica para httpd
chmod +x deploy/setup_httpd_existing.sh
sudo ./deploy/setup_httpd_existing.sh
```

### 2. Deploy da Aplicação
```bash
# Deploy da aplicação
chmod +x deploy/deploy.sh
sudo ./deploy/deploy.sh
```

### 3. Verificação
```bash
# Verificar status
chmod +x deploy/check_status.sh
sudo ./deploy/check_status.sh
```

## O que o script setup_httpd_existing.sh faz:

### ✅ **Verificações de Segurança:**
1. Verifica se httpd está rodando
2. Não interfere com configurações existentes
3. Apenas adiciona nova configuração

### ✅ **Configurações Aplicadas:**
1. **mod_wsgi** - Verifica e configura se necessário
2. **Virtual Host** - Cria configuração isolada
3. **Python Environment** - Cria ambiente virtual isolado
4. **Permissões** - Configura usuário `apache` (padrão httpd)
5. **Logs Separados** - Logs isolados para esta aplicação

### ✅ **Arquivos Criados:**
```
/var/www/controle_estoque_db/          # Aplicação
/etc/httpd/conf.d/controle-estoque.conf   # Virtual Host
/etc/logrotate.d/controle-estoque          # Rotação de logs
/var/log/httpd/controle_estoque_*.log      # Logs específicos
```

## Estrutura Final no Servidor

```
/var/www/controle_estoque_db/
├── app.py                 # Aplicação Flask
├── wsgi.py               # Interface WSGI
├── requirements.txt      # Dependências Python
├── venv/                 # Ambiente virtual Python
├── static/               # Arquivos CSS/JS/imagens
├── templates/            # Templates HTML
├── utils/                # Módulos Python da aplicação
├── logs/                 # Logs da aplicação
├── relatorios/          # Base de dados SQLite e relatórios
└── temp/                # Arquivos temporários
```

## Configuração do Virtual Host

O arquivo `/etc/httpd/conf.d/controle-estoque.conf` será criado com:

```apache
<VirtualHost *:80>
    ServerName seu-dominio.com.br
    ServerAlias www.seu-dominio.com.br
    
    DocumentRoot /var/www/controle_estoque_db
    
    WSGIDaemonProcess controle_estoque python-path=/var/www/controle_estoque_db python-home=/var/www/controle_estoque_db/venv
    WSGIProcessGroup controle_estoque
    WSGIScriptAlias / /var/www/controle_estoque_db/wsgi.py
    WSGIApplicationGroup %{GLOBAL}
    
    <Directory /var/www/controle_estoque_db>
        WSGIApplicationGroup %{GLOBAL}
        Require all granted
        Options -Indexes
    </Directory>
    
    Alias /static /var/www/controle_estoque_db/static
    Alias /relatorios /var/www/controle_estoque_db/relatorios
    
    ErrorLog /var/log/httpd/controle_estoque_error.log
    CustomLog /var/log/httpd/controle_estoque_access.log combined
</VirtualHost>
```

## Comandos Específicos para httpd

### 🔧 **Gerenciamento do Serviço:**
```bash
# Status do httpd
sudo systemctl status httpd

# Recarregar configuração (SEM REINICIAR)
sudo systemctl reload httpd

# Testar configuração
sudo httpd -t

# Ver módulos carregados
httpd -M | grep wsgi
```

### 📊 **Monitoramento:**
```bash
# Logs específicos da aplicação
sudo tail -f /var/log/httpd/controle_estoque_error.log
sudo tail -f /var/log/httpd/controle_estoque_access.log

# Logs da aplicação Python
sudo tail -f /var/www/controle_estoque_db/logs/app.log

# Verificar processos
ps aux | grep httpd
ps aux | grep python | grep controle
```

### 🔍 **Debug de Problemas:**
```bash
# Verificar se mod_wsgi está carregado
httpd -M | grep wsgi

# Verificar configuração específica
httpd -S | grep controle

# Verificar permissões
ls -la /var/www/controle_estoque_db/
ls -la /var/www/controle_estoque_db/wsgi.py

# Verificar usuário dos processos
ps aux | grep httpd | head -5
```

## Solução de Problemas Específicos do httpd

### Problema: mod_wsgi não encontrado
```bash
# CentOS/RHEL 7/8
sudo yum install python3-mod_wsgi

# CentOS/RHEL 9/Fedora
sudo dnf install python3-mod_wsgi

# Verificar instalação
find /usr/lib64/httpd/modules -name "*wsgi*"
```

### Problema: Erro 500 Internal Server Error
```bash
# Verificar logs específicos
sudo tail -f /var/log/httpd/controle_estoque_error.log

# Verificar SELinux (se ativo)
sudo setsebool -P httpd_can_network_connect 1
sudo chcon -R -t httpd_exec_t /var/www/controle_estoque_db/

# Verificar permissões
sudo chown -R apache:apache /var/www/controle_estoque_db/
sudo chmod -R 755 /var/www/controle_estoque_db/
```

### Problema: Conflito de porta/domínio
```bash
# Verificar outros Virtual Hosts
httpd -S

# Verificar configurações conflitantes
grep -r "ServerName seu-dominio" /etc/httpd/conf.d/
```

## Personalização

### 1. **Alterar domínio:**
```bash
sudo nano /etc/httpd/conf.d/controle-estoque.conf
# Alterar ServerName e ServerAlias
sudo systemctl reload httpd
```

### 2. **Configurar HTTPS:**
```bash
# Descomentar seção HTTPS no arquivo conf
# Configurar certificados SSL
# Recarregar httpd
```

### 3. **Ajustar recursos:**
```bash
# Editar WSGIDaemonProcess no Virtual Host
# Exemplo: processes=2 threads=15 maximum-requests=1000
```

## Backup e Manutenção

### 📦 **Backup Automático:**
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/controle_estoque_db"
APP_DIR="/var/www/controle_estoque_db"

mkdir -p $BACKUP_DIR
tar -czf "$BACKUP_DIR/backup_$DATE.tar.gz" -C "$APP_DIR" .
find $BACKUP_DIR -name "backup_*.tar.gz" -mtime +30 -delete

# Adicionar ao crontab: 0 2 * * * /usr/local/bin/backup_controle.sh
```

### 🔄 **Atualizações:**
```bash
# Para atualizar a aplicação
cd /var/www/controle_estoque_db
sudo -u apache git pull  # se usando Git
sudo systemctl reload httpd  # recarregar sem afetar outras apps
```

## Segurança Adicional

### 🔒 **SELinux (se ativo):**
```bash
# Configurar contexto SELinux
sudo setsebool -P httpd_can_network_connect 1
sudo chcon -R -t httpd_exec_t /var/www/controle_estoque_db/wsgi.py
sudo chcon -R -t httpd_sys_content_t /var/www/controle_estoque_db/static/
sudo chcon -R -t httpd_sys_rw_content_t /var/www/controle_estoque_db/logs/
sudo chcon -R -t httpd_sys_rw_content_t /var/www/controle_estoque_db/relatorios/
```

### 🔐 **Firewall:**
```bash
# Se necessário abrir porta 80/443 para o domínio específico
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## Resumo dos Diferenciais

| Aspecto | Apache2 Novo | httpd Existente |
|---------|-------------|----------------|
| **Reinicialização** | Restart completo | Apenas reload |
| **Configuração** | Sites-available | conf.d |
| **Usuário** | www-data | apache |
| **Comandos** | apache2ctl | httpd |
| **Logs** | /var/log/apache2/ | /var/log/httpd/ |
| **Módulos** | a2enmod | Configuração direta |
| **Impacto** | Pode afetar outras apps | Zero impacto |

---

**✅ Este guia garante que sua aplicação seja instalada sem afetar outras aplicações já rodando no httpd!**