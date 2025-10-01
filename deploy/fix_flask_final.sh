#!/bin/bash
# Script para corrigir permissões e configurar Flask

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CORRIGINDO PERMISSÕES E CONFIGURANDO FLASK ===${NC}"

APP_DIR="/var/www/controle_estoque_db"

echo -e "${YELLOW}1. Corrigindo permissões de todos os diretórios...${NC}"
cd "$APP_DIR"

# Corrigir propriedade de todos os arquivos
chown -R http:http .
echo "✓ Propriedade definida para http:http"

# Corrigir permissões básicas
chmod -R 755 .
echo "✓ Permissões básicas aplicadas"

# Permissões especiais para diretórios de escrita
chmod -R 775 logs relatorios temp 2>/dev/null
echo "✓ Permissões de escrita para logs, relatorios, temp"

# Executável para wsgi.py
chmod +x wsgi.py
echo "✓ wsgi.py marcado como executável"

echo -e "\n${YELLOW}2. Ativando ambiente virtual...${NC}"
if [ -d "venv" ]; then
    echo "✓ Ambiente virtual encontrado"
    # Corrigir permissões do venv também
    chown -R http:http venv
    chmod -R 755 venv
else
    echo "Criando ambiente virtual..."
    python3 -m venv venv
    chown -R http:http venv
    chmod -R 755 venv
    echo "✓ Ambiente virtual criado"
fi

echo -e "\n${YELLOW}3. Instalando dependências Flask...${NC}"
source venv/bin/activate

# Instalar/atualizar dependências essenciais
pip install --upgrade pip
pip install Flask==3.1.1 Werkzeug==3.1.3

# Instalar outras dependências se requirements.txt existir
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
    echo "✓ Dependências do requirements.txt instaladas"
else
    # Instalar dependências comuns
    pip install pandas openpyxl python-dateutil pytz
    echo "✓ Dependências básicas instaladas"
fi

echo -e "\n${YELLOW}4. Testando app.py...${NC}"
cd "$APP_DIR"

# Testar se app.py funciona agora
python3 -c "
import sys
sys.path.insert(0, '/var/www/controle_estoque_db')
try:
    import app
    print('✅ app.py importa corretamente!')
    # Verificar se tem variável 'app'
    if hasattr(app, 'app'):
        print('✅ Variável app encontrada')
    else:
        print('⚠️ Variável app não encontrada - verificando...')
        print('Atributos disponíveis:', [attr for attr in dir(app) if not attr.startswith('_')])
except Exception as e:
    print(f'❌ Erro ao importar app.py: {e}')
    import traceback
    traceback.print_exc()
"

echo -e "\n${YELLOW}5. Criando wsgi.py otimizado para sua aplicação...${NC}"

# Backup do wsgi atual
cp wsgi.py wsgi.py.backup.$(date +%H%M%S)

# WSGI otimizado
cat > wsgi.py << 'EOL'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WSGI Configuration for Controle de Estoque Flask App
Otimizado com correção de permissões
"""

import sys
import os
import logging

# Configurar logging básico
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Definir diretório da aplicação
APP_DIR = '/var/www/controle_estoque_db'
sys.path.insert(0, APP_DIR)

# Mudar para diretório da aplicação
os.chdir(APP_DIR)

# Variáveis de ambiente
os.environ['FLASK_APP'] = 'app.py'
os.environ['FLASK_ENV'] = 'production'

# Middleware para subdiretório /estoque
class ReverseProxied(object):
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        script_name = '/estoque'
        environ['SCRIPT_NAME'] = script_name
        path_info = environ['PATH_INFO']
        if path_info.startswith(script_name):
            environ['PATH_INFO'] = path_info[len(script_name):]
        return self.app(environ, start_response)

try:
    logger.info("Carregando aplicação Flask...")
    
    # Importar aplicação
    import app
    
    # Tentar diferentes formas de obter a aplicação Flask
    if hasattr(app, 'app'):
        application = app.app
        logger.info("Aplicação encontrada em app.app")
    elif hasattr(app, 'create_app'):
        application = app.create_app()
        logger.info("Aplicação criada via app.create_app()")
    elif hasattr(app, 'application'):
        application = app.application
        logger.info("Aplicação encontrada em app.application")
    else:
        # Procurar por instância Flask no módulo
        from flask import Flask
        flask_instances = [getattr(app, attr) for attr in dir(app) 
                          if isinstance(getattr(app, attr), Flask)]
        if flask_instances:
            application = flask_instances[0]
            logger.info("Instância Flask encontrada automaticamente")
        else:
            raise Exception("Nenhuma instância Flask encontrada no módulo app")
    
    # Configurações de produção
    application.config['DEBUG'] = False
    application.config['TESTING'] = False
    
    # Aplicar middleware para subdiretório
    application = ReverseProxied(application)
    
    logger.info("✅ Aplicação Flask configurada com sucesso")

except Exception as e:
    logger.error(f"❌ Erro ao carregar aplicação: {e}")
    
    # Aplicação de fallback mais informativa
    from flask import Flask, request
    
    application = Flask(__name__)
    
    @application.route('/')
    @application.route('/<path:path>')
    def error_info(path=''):
        import traceback
        error_details = traceback.format_exc()
        
        return f'''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Controle de Estoque - Erro de Configuração</title>
            <meta charset="utf-8">
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                .error {{ background: #ffebee; border: 1px solid #f44336; padding: 15px; border-radius: 5px; }}
                .success {{ background: #e8f5e8; border: 1px solid #4caf50; padding: 15px; border-radius: 5px; }}
                .code {{ background: #f5f5f5; padding: 10px; border-radius: 3px; font-family: monospace; }}
                h1 {{ color: #d32f2f; }}
                h2 {{ color: #1976d2; }}
            </style>
        </head>
        <body>
            <h1>🚨 Controle de Estoque - Erro de Configuração</h1>
            
            <div class="error">
                <h2>Erro Principal:</h2>
                <p><strong>{e}</strong></p>
            </div>
            
            <h2>📋 Informações de Debug:</h2>
            <ul>
                <li><strong>Diretório atual:</strong> {os.getcwd()}</li>
                <li><strong>Python Path:</strong> {sys.path[0]}</li>
                <li><strong>Usuário:</strong> {os.getenv("USER", "desconhecido")}</li>
                <li><strong>Caminho solicitado:</strong> {request.path}</li>
            </ul>
            
            <h2>📂 Arquivos no Diretório:</h2>
            <div class="code">
            {'<br>'.join(os.listdir(APP_DIR))}
            </div>
            
            <h2>🔧 Detalhes do Erro:</h2>
            <div class="code">
            {error_details.replace(chr(10), '<br>').replace(' ', '&nbsp;')}
            </div>
            
            <h2>✅ Próximos Passos:</h2>
            <ol>
                <li>Verifique se app.py existe e é válido</li>
                <li>Execute: <code>sudo ./deploy/fix_flask_final.sh</code></li>
                <li>Verifique logs: <code>tail -f /var/log/httpd/error_log</code></li>
            </ol>
        </body>
        </html>
        '''
    
    application = ReverseProxied(application)

if __name__ == "__main__":
    application.run()
EOL

echo "✓ wsgi.py otimizado criado"

echo -e "\n${YELLOW}6. Ajustando permissões finais...${NC}"
chown http:http wsgi.py
chmod +x wsgi.py

echo -e "\n${YELLOW}7. Recarregando Apache...${NC}"
systemctl reload httpd
sleep 3

echo -e "\n${YELLOW}8. Testando aplicação...${NC}"
HTTP_CODE=$(curl -s -o /tmp/flask_test.html -w "%{http_code}" http://localhost/estoque/)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Sucesso! HTTP $HTTP_CODE${NC}"
    
    # Verificar conteúdo
    if grep -q "Controle de Estoque" /tmp/flask_test.html; then
        if grep -q "Erro de Configuração" /tmp/flask_test.html; then
            echo -e "${YELLOW}⚠️ Aplicação carregou mas ainda há problemas de configuração${NC}"
            echo "Verifique: http://localhost/estoque/ para detalhes"
        else
            echo -e "${GREEN}🎉 APLICAÇÃO FLASK FUNCIONANDO PERFEITAMENTE!${NC}"
        fi
    else
        echo -e "${YELLOW}ℹ️ Aplicação respondendo - verifique manualmente${NC}"
    fi
    
else
    echo -e "${RED}❌ Ainda com problemas: HTTP $HTTP_CODE${NC}"
    echo "Logs recentes:"
    tail -5 /var/log/httpd/error_log
fi

echo -e "\n${GREEN}=== CONFIGURAÇÃO CONCLUÍDA ===${NC}"
echo -e "${YELLOW}URLs para teste:${NC}"
echo "• Principal: http://localhost/estoque/"
echo "• Logs: tail -f /var/log/httpd/error_log"

echo -e "\n${YELLOW}Status dos arquivos:${NC}"
ls -la "$APP_DIR" | grep -E "(app\.py|wsgi\.py|logs|temp|relatorios)" | head -10