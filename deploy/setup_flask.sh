#!/bin/bash
# Script para configurar aplicação Flask completa

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CONFIGURANDO APLICAÇÃO FLASK COMPLETA ===${NC}"

APP_DIR="/var/www/controle_estoque_db"
SOURCE_DIR="/tmp/controle_estoque_db"

# 1. Verificar se arquivos fonte existem
echo -e "${YELLOW}1. Verificando arquivos fonte...${NC}"
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}✗ Diretório fonte não encontrado: $SOURCE_DIR${NC}"
    echo "Certifique-se de que os arquivos estão em /tmp/controle_estoque_db/"
    exit 1
fi

echo "Arquivos encontrados:"
ls -la "$SOURCE_DIR" | grep -E "(app\.py|utils|templates|static|requirements)"

# 2. Criar backup do wsgi.py atual (que está funcionando)
echo -e "\n${YELLOW}2. Fazendo backup do wsgi.py atual...${NC}"
cp "$APP_DIR/wsgi.py" "$APP_DIR/wsgi.py.backup.$(date +%Y%m%d_%H%M%S)"

# 3. Copiar arquivos da aplicação
echo -e "\n${YELLOW}3. Copiando arquivos da aplicação...${NC}"

# Copiar arquivos principais
cp "$SOURCE_DIR/app.py" "$APP_DIR/" 2>/dev/null && echo "✓ app.py copiado" || echo "✗ app.py não encontrado"

# Copiar diretórios
for dir in utils templates static; do
    if [ -d "$SOURCE_DIR/$dir" ]; then
        cp -r "$SOURCE_DIR/$dir" "$APP_DIR/"
        echo "✓ $dir/ copiado"
    else
        echo "✗ $dir/ não encontrado"
    fi
done

# Copiar outros arquivos importantes
for file in requirements.txt config.py; do
    if [ -f "$SOURCE_DIR/$file" ]; then
        cp "$SOURCE_DIR/$file" "$APP_DIR/"
        echo "✓ $file copiado"
    else
        echo "! $file não encontrado (opcional)"
    fi
done

# 4. Criar diretórios necessários
echo -e "\n${YELLOW}4. Criando diretórios necessários...${NC}"
mkdir -p "$APP_DIR"/{logs,relatorios,temp}
echo "✓ Diretórios logs, relatorios, temp criados"

# 5. Configurar ambiente virtual Python
echo -e "\n${YELLOW}5. Configurando ambiente virtual Python...${NC}"

cd "$APP_DIR"

if [ ! -d "venv" ]; then
    echo "Criando ambiente virtual..."
    python3 -m venv venv
    echo "✓ Ambiente virtual criado"
else
    echo "✓ Ambiente virtual já existe"
fi

# Ativar ambiente virtual e instalar dependências
source venv/bin/activate

# 6. Instalar dependências Python
echo -e "\n${YELLOW}6. Instalando dependências Python...${NC}"

# Usar requirements.txt se existir, senão instalar pacotes essenciais
if [ -f "requirements.txt" ]; then
    echo "Instalando do requirements.txt..."
    pip install --upgrade pip
    pip install -r requirements.txt
else
    echo "Instalando pacotes essenciais..."
    pip install --upgrade pip
    pip install Flask==3.1.1 Werkzeug==3.1.3 Jinja2==3.1.6
    pip install pandas==2.3.1 openpyxl==3.1.5 numpy==2.3.2
    pip install python-dateutil pytz
fi

echo "✓ Dependências instaladas"

# 7. Criar wsgi.py para Flask
echo -e "\n${YELLOW}7. Criando wsgi.py para aplicação Flask...${NC}"

cat > "$APP_DIR/wsgi.py" << 'EOL'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WSGI Configuration for Controle de Estoque Flask App
Configurado para rodar em /estoque
"""

import sys
import os
import logging

# Configurar logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Adicionar o diretório da aplicação ao Python path
sys.path.insert(0, '/var/www/controle_estoque_db/')

# Definir variáveis de ambiente
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
    # Tentar importar aplicação Flask
    logger.info("Importando aplicação Flask...")
    from app import app as application
    
    # Configurações para produção
    application.config['DEBUG'] = False
    application.config['TESTING'] = False
    
    # Aplicar middleware para subdiretório
    application = ReverseProxied(application, script_name='/estoque')
    
    logger.info("Aplicação Flask carregada com sucesso")
    
except ImportError as e:
    logger.error(f"Erro ao importar app.py: {e}")
    
    # Aplicação de fallback
    from flask import Flask
    application = Flask(__name__)
    
    @application.route('/')
    def error_page():
        return f'''
        <h1>❌ Erro ao carregar aplicação</h1>
        <p><strong>Erro:</strong> {e}</p>
        <p>Verifique se app.py existe e se as dependências estão instaladas.</p>
        <p>Logs: /var/log/httpd/error_log</p>
        '''
    
    application = ReverseProxied(application, script_name='/estoque')

except Exception as e:
    logger.error(f"Erro geral: {e}")
    
    # Aplicação de fallback para outros erros
    from flask import Flask
    application = Flask(__name__)
    
    @application.route('/')
    def error_page():
        return f'''
        <h1>❌ Erro na aplicação</h1>
        <p><strong>Erro:</strong> {e}</p>
        <p>Verifique os logs para mais detalhes.</p>
        '''
    
    application = ReverseProxied(application, script_name='/estoque')

if __name__ == "__main__":
    application.run()
EOL

# 8. Ajustar permissões
echo -e "\n${YELLOW}8. Ajustando permissões...${NC}"
chown -R http:http "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod -R 775 "$APP_DIR"/{logs,relatorios,temp}
chmod +x "$APP_DIR/wsgi.py"

# 9. Verificar se app.py é válido
echo -e "\n${YELLOW}9. Verificando app.py...${NC}"
cd "$APP_DIR"
if source venv/bin/activate && python -c "import app; print('✓ app.py importa corretamente')" 2>/dev/null; then
    echo -e "${GREEN}✓ app.py é válido${NC}"
else
    echo -e "${YELLOW}⚠ Problemas com app.py - wsgi.py vai mostrar erro detalhado${NC}"
fi

# 10. Recarregar httpd
echo -e "\n${YELLOW}10. Recarregando httpd...${NC}"
systemctl reload httpd

# 11. Aguardar e testar
echo -e "\n${YELLOW}11. Aguardando e testando (5 segundos)...${NC}"
sleep 5

# 12. Teste final
echo -e "\n${YELLOW}12. Teste final:${NC}"
HTTP_CODE=$(curl -s -o /tmp/flask_test.html -w "%{http_code}" http://localhost/estoque/)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Sucesso! HTTP $HTTP_CODE${NC}"
    
    # Verificar se é a aplicação Flask ou página de erro
    if grep -q "Controle de Estoque" /tmp/flask_test.html; then
        echo -e "${GREEN}🎉 Aplicação Flask funcionando!${NC}"
    elif grep -q "Erro" /tmp/flask_test.html; then
        echo -e "${YELLOW}⚠ Aplicação carregou mas há erros - verifique a página${NC}"
    else
        echo -e "${YELLOW}ℹ Aplicação respondendo - verifique manualmente${NC}"
    fi
    
else
    echo -e "${RED}❌ Erro HTTP: $HTTP_CODE${NC}"
    echo "Últimas linhas do log:"
    tail -10 /var/log/httpd/error_log
fi

echo -e "\n${GREEN}=== CONFIGURAÇÃO FLASK CONCLUÍDA ===${NC}"
echo -e "${YELLOW}URLs para teste:${NC}"
echo "• Aplicação: http://localhost/estoque/"
echo "• Logs: tail -f /var/log/httpd/error_log"
echo ""
echo -e "${YELLOW}Estrutura final:${NC}"
ls -la "$APP_DIR" | head -15