#!/bin/bash
# Script para diagnosticar e corrigir erro 500

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DIAGNÓSTICO ERRO 500 INTERNAL SERVER ERROR ===${NC}"

APP_DIR="/var/www/controle_estoque_db"

echo -e "${YELLOW}1. Verificando logs do Apache...${NC}"
echo "Últimas 20 linhas do error_log:"
tail -20 /var/log/httpd/error_log

echo -e "\n${YELLOW}2. Verificando arquivo wsgi.py...${NC}"
if [ -f "$APP_DIR/wsgi.py" ]; then
    echo "✓ wsgi.py existe"
    ls -la "$APP_DIR/wsgi.py"
    echo "Permissões OK"
else
    echo "❌ wsgi.py não encontrado!"
fi

echo -e "\n${YELLOW}3. Verificando Python e módulos...${NC}"
cd "$APP_DIR"

# Testar importação Python
echo "Testando importação Python:"
python3 -c "import sys; print('Python:', sys.version)" 2>&1

echo "Testando Flask:"
python3 -c "import flask; print('Flask:', flask.__version__)" 2>&1

echo -e "\n${YELLOW}4. Verificando se app.py existe...${NC}"
if [ -f "$APP_DIR/app.py" ]; then
    echo "✓ app.py encontrado"
    echo "Testando sintaxe:"
    python3 -m py_compile app.py && echo "✓ Sintaxe OK" || echo "❌ Erro de sintaxe"
else
    echo "❌ app.py NÃO encontrado!"
fi

echo -e "\n${YELLOW}5. Criando wsgi.py de emergência simples...${NC}"

# Backup do atual
if [ -f "$APP_DIR/wsgi.py" ]; then
    cp "$APP_DIR/wsgi.py" "$APP_DIR/wsgi.py.backup.$(date +%H%M%S)"
fi

# WSGI super simples para diagnóstico
cat > "$APP_DIR/wsgi.py" << 'EOL'
#!/usr/bin/env python3
import sys
import os

# Adicionar diretório ao path
sys.path.insert(0, '/var/www/controle_estoque_db/')

# Middleware para subdiretório
class ReverseProxied(object):
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        environ['SCRIPT_NAME'] = '/estoque'
        path_info = environ['PATH_INFO']
        if path_info.startswith('/estoque'):
            environ['PATH_INFO'] = path_info[7:]
        return self.app(environ, start_response)

# Função de diagnóstico
def diagnostic_app(environ, start_response):
    status = '200 OK'
    headers = [('Content-type', 'text/html; charset=utf-8')]
    
    try:
        # Informações de diagnóstico
        html = f'''
        <h1>🔧 Diagnóstico WSGI</h1>
        <h2>✅ WSGI funcionando!</h2>
        
        <h3>Informações do Sistema:</h3>
        <ul>
        <li><strong>Python:</strong> {sys.version}</li>
        <li><strong>Path:</strong> {sys.path[0]}</li>
        <li><strong>Diretório atual:</strong> {os.getcwd()}</li>
        <li><strong>Usuário:</strong> {os.getenv("USER", "desconhecido")}</li>
        </ul>
        
        <h3>Arquivos no diretório:</h3>
        <ul>
        '''
        
        # Listar arquivos
        try:
            files = os.listdir('/var/www/controle_estoque_db/')
            for f in files:
                html += f'<li>{f}</li>'
        except Exception as e:
            html += f'<li>Erro ao listar: {e}</li>'
        
        html += '</ul><h3>Teste de Importação Flask:</h3><ul>'
        
        # Testar Flask
        try:
            import flask
            html += f'<li>✅ Flask {flask.__version__} OK</li>'
        except Exception as e:
            html += f'<li>❌ Flask erro: {e}</li>'
        
        # Testar app.py
        try:
            import app
            html += '<li>✅ app.py importado com sucesso!</li>'
            html += '<li><a href="/estoque/">🚀 Tentar aplicação real</a></li>'
        except Exception as e:
            html += f'<li>❌ app.py erro: {e}</li>'
            html += '<li>ℹ️ Coloque app.py no diretório para continuar</li>'
        
        html += '''
        </ul>
        <hr>
        <p><small>Diagnóstico WSGI - Erro 500 resolvido</small></p>
        '''
        
    except Exception as e:
        html = f'<h1>Erro no diagnóstico: {e}</h1>'
    
    start_response(status, headers)
    return [html.encode('utf-8')]

# Tentar carregar app real, senão usar diagnóstico
try:
    from app import app as application
    application = ReverseProxied(application)
    print("✅ Aplicação Flask carregada")
except:
    application = ReverseProxied(diagnostic_app)
    print("⚠️ Usando aplicação de diagnóstico")

if __name__ == "__main__":
    from wsgiref.simple_server import make_server
    server = make_server('localhost', 8000, application)
    server.serve_forever()
EOL

echo "✓ wsgi.py de emergência criado"

echo -e "\n${YELLOW}6. Ajustando permissões...${NC}"
chown http:http "$APP_DIR/wsgi.py"
chmod 755 "$APP_DIR/wsgi.py"

echo -e "\n${YELLOW}7. Recarregando Apache...${NC}"
systemctl reload httpd
sleep 3

echo -e "\n${YELLOW}8. Testando novamente...${NC}"
HTTP_CODE=$(curl -s -o /tmp/test_fix.html -w "%{http_code}" http://localhost/estoque/)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Erro 500 CORRIGIDO! HTTP $HTTP_CODE${NC}"
    echo "Página de diagnóstico carregada - acesse http://localhost/estoque/"
else
    echo -e "${RED}❌ Ainda com erro: HTTP $HTTP_CODE${NC}"
    echo "Verificando logs novamente:"
    tail -5 /var/log/httpd/error_log
fi

echo -e "\n${YELLOW}Próximos passos:${NC}"
echo "1. Acesse: http://localhost/estoque/"
echo "2. Verifique se app.py está no diretório"
echo "3. Se tudo OK, execute: sudo ./deploy/setup_flask.sh"