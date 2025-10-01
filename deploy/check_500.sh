#!/bin/bash
# Script rápido para ver erro 500

echo "=== LOGS DE ERRO 500 ==="
echo "Últimas 10 linhas do error_log:"
echo "----------------------------------------"
tail -10 /var/log/httpd/error_log | grep -E "(error|Error|ERROR|exception|Exception|wsgi|WSGI|estoque)"
echo "----------------------------------------"

echo ""
echo "=== VERIFICAÇÃO RÁPIDA ==="
echo "wsgi.py existe: $(test -f /var/www/controle_estoque_db/wsgi.py && echo 'SIM' || echo 'NÃO')"
echo "app.py existe: $(test -f /var/www/controle_estoque_db/app.py && echo 'SIM' || echo 'NÃO')"
echo "Permissões wsgi.py: $(ls -la /var/www/controle_estoque_db/wsgi.py 2>/dev/null || echo 'arquivo não encontrado')"

echo ""
echo "=== TESTE PYTHON ==="
cd /var/www/controle_estoque_db
python3 -c "
import sys
print(f'Python: {sys.version}')
try:
    import flask
    print(f'Flask: {flask.__version__}')
except:
    print('Flask: NÃO INSTALADO')
try:
    import app
    print('app.py: OK')
except Exception as e:
    print(f'app.py: ERRO - {e}')
" 2>&1

echo ""
echo "Execute para corrigir: sudo ./deploy/fix_500_error.sh"