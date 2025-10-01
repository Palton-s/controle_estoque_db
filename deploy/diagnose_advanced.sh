#!/bin/bash
# Script corrigido para o ambiente específico do servidor

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== DIAGNÓSTICO AVANÇADO E CORREÇÃO ===${NC}"

# Detectar usuário correto do httpd
HTTPD_USER=$(ps aux | grep httpd | grep -v root | head -1 | awk '{print $1}')
if [ -z "$HTTPD_USER" ]; then
    HTTPD_USER="nobody"  # fallback comum
fi

echo -e "${YELLOW}Usuário httpd detectado: $HTTPD_USER${NC}"

APP_DIR="/var/www/controle_estoque_db"

# 1. Verificar usuário e grupo corretos
echo -e "\n${YELLOW}1. Verificando usuários do sistema...${NC}"
echo "Usuários disponíveis relacionados ao httpd:"
grep -E "(apache|httpd|www-data|nobody)" /etc/passwd || echo "Nenhum usuário específico encontrado"

# 2. Verificar processo httpd
echo -e "\n${YELLOW}2. Processos httpd em execução:${NC}"
ps aux | grep httpd | grep -v grep

# 3. Verificar configuração de Virtual Hosts
echo -e "\n${YELLOW}3. Verificando Virtual Hosts configurados:${NC}"
httpd -S 2>/dev/null | head -20

# 4. Testar WSGI especificamente
echo -e "\n${YELLOW}4. Testando acesso direto ao WSGI:${NC}"
if [ -f "$APP_DIR/wsgi.py" ]; then
    echo "Arquivo wsgi.py existe"
    echo "Conteúdo do wsgi.py:"
    head -20 "$APP_DIR/wsgi.py"
else
    echo "wsgi.py NÃO existe!"
fi

# 5. Verificar se o Python funciona
echo -e "\n${YELLOW}5. Testando Python:${NC}"
cd "$APP_DIR"
if [ -f "venv/bin/python" ]; then
    echo "Virtual env existe"
    venv/bin/python --version
else
    echo "Virtual env NÃO existe"
    python3 --version
fi

# 6. Criar ambiente virtual se não existir
if [ ! -d "$APP_DIR/venv" ]; then
    echo -e "${YELLOW}Criando ambiente virtual...${NC}"
    cd "$APP_DIR"
    python3 -m venv venv
    source venv/bin/activate
    pip install flask
fi

# 7. Ajustar permissões com usuário correto
echo -e "\n${YELLOW}6. Corrigindo permissões...${NC}"
chown -R $HTTPD_USER:$HTTPD_USER "$APP_DIR" 2>/dev/null || chown -R nobody:nobody "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod +x "$APP_DIR/wsgi.py"

# 8. Verificar se mod_wsgi consegue carregar o arquivo
echo -e "\n${YELLOW}7. Testando importação Python:${NC}"
cd "$APP_DIR"
if [ -f "venv/bin/python" ]; then
    venv/bin/python -c "
import sys
sys.path.insert(0, '/var/www/controle_estoque_db/')
try:
    import wsgi
    print('✓ wsgi.py carrega corretamente')
except Exception as e:
    print('✗ Erro ao carregar wsgi.py:', e)
"
fi

# 9. Verificar logs em tempo real enquanto testa
echo -e "\n${YELLOW}8. Testando acesso e monitorando logs:${NC}"
echo "Iniciando monitoramento de logs..."

# Fazer requisição e capturar logs simultaneamente
(
    sleep 1
    echo "Fazendo requisição HTTP..."
    curl -v http://localhost/estoque/ 2>&1
    echo ""
    echo "Fazendo requisição com wget..."
    wget -O- http://localhost/estoque/ 2>&1
) &

# Monitorar logs por alguns segundos
timeout 10 tail -f /var/log/httpd/error_log &
TAIL_PID=$!

wait

# Parar monitoramento
kill $TAIL_PID 2>/dev/null

echo -e "\n${YELLOW}9. Verificação final da configuração:${NC}"
echo "Conteúdo atual do arquivo de configuração:"
cat /etc/httpd/conf.d/controle-estoque.conf

echo -e "\n${GREEN}=== DIAGNÓSTICO CONCLUÍDO ===${NC}"
echo -e "${YELLOW}Se ainda não funcionar, execute estes comandos manuais:${NC}"
echo "1. systemctl restart httpd"
echo "2. tail -f /var/log/httpd/error_log &"
echo "3. curl -v http://localhost/estoque/"
echo "4. Verificar se existe outros Virtual Hosts conflitantes:"
echo "   httpd -S | grep -i virtual"