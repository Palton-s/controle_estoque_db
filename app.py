import os
import sys
import re
import sqlite3
import shutil
from datetime import datetime
from werkzeug.utils import secure_filename

from flask import Flask, render_template, request, send_file, abort, jsonify, redirect, url_for

# Importar todos os handlers
from utils.db_handler import (
    verificar_bem,
    marcar_bem_localizado,
    gerar_planilhas_localizacao,
    buscar_localizacao_existente,
    obter_bem_por_numero,
    atualizar_bem,
    excluir_bem,
    criar_novo_bem,
    buscar_bens_por_nome,
    contar_bens,  # Certifique-se que esta função existe!
    obter_bens_paginados
)

from utils.excel_importer import importar_excel_para_sqlite, verificar_estrutura_excel
from utils.logger import logger

app = Flask(__name__)

# ==============================
# Filtros personalizados para Jinja2
# ==============================
@app.template_filter('number_format')
def number_format_filter(value):
    """Filtro para formatar números com separadores de milhar"""
    try:
        if value is None:
            return "0"
        return f"{int(value):,}".replace(",", ".")
    except (ValueError, TypeError):
        return str(value)

@app.template_filter('pluralize')
def pluralize_filter(value, singular, plural):
    """Filtro para pluralizar palavras baseado no valor"""
    try:
        num = int(value)
        return singular if num == 1 else plural
    except (ValueError, TypeError):
        return plural

# ==============================
# Utilitário de caminho (PyInstaller)
# ==============================
def caminho_relativo(pasta: str) -> str:
    """Retorna caminho absoluto, mesmo empacotado com PyInstaller."""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, pasta)
    return os.path.join(os.path.abspath("."), pasta)

# ▶️ Agora a FONTE é o BANCO (não mais Excel)
DB_PATH = os.path.join(caminho_relativo("relatorios"), "controle_patrimonial.db")

# ==============================
# Funções auxiliares
# ==============================
def _carregar_dados_bancos():
    """Carrega contagens do banco de forma otimizada"""
    try:
        contagens = contar_bens(DB_PATH)
        
        # Retornar apenas as contagens para a página principal
        return {
            'localizados_count': contagens['localizados'],
            'nao_localizados_count': contagens['nao_localizados'],
            'total_count': contagens['total']
        }
    except Exception as e:
        logger.error(f"Erro ao carregar contagens do banco: {str(e)}")
        return {'localizados_count': 0, 'nao_localizados_count': 0, 'total_count': 0}
    
def _processar_bem(numero_bem: str, localizacao: str = None):
    """Processa a localização de um bem"""
    try:
        # Se localização NÃO foi informada → tenta completar a partir do próprio DB
        if not localizacao:
            localizacao = buscar_localizacao_existente(numero_bem, DB_PATH)

        # Verifica se o bem existe no DB
        encontrado, erro = verificar_bem(numero_bem, DB_PATH)
        if encontrado:
            # Marca como localizado (e atualiza localização se houver)
            mensagem = marcar_bem_localizado(numero_bem, DB_PATH, localizacao)
        else:
            mensagem = erro or 'Bem não encontrado.'
            
        # Buscar detalhes do bem para exibir no modal
        bem_detalhes = _buscar_detalhes_bem(numero_bem, localizacao)
        
        return {
            'mensagem': mensagem,
            'bem_detalhes': bem_detalhes,
            'localizacao_informada': localizacao,
            'show_modal': True
        }
        
    except Exception as e:
        logger.error(f"Erro ao processar bem {numero_bem}: {str(e)}")
        return {
            'mensagem': 'Erro interno ao processar o bem.',
            'bem_detalhes': None,
            'localizacao_informada': localizacao,
            'show_modal': True
        }

def _buscar_detalhes_bem(numero_bem: str, localizacao: str = None):
    """Busca detalhes de um bem específico - Versão CRUD"""
    try:
        bem = obter_bem_por_numero(DB_PATH, numero_bem)
        
        if bem:
            # Usar a localização fornecida pelo usuário se disponível
            localizacao_final = (
                localizacao or 
                bem['localizacao'] or 
                'Não informada'
            )
            
            return {
                'id': bem['id'],
                'nome': bem['nome'] or 'Não informado',
                'numero': bem['numero'] or 'Não informado',
                'situacao': bem['situacao'] or 'Pendente',
                'localizacao': localizacao_final,
                'data_criacao': bem['data_criacao'],
                'data_localizacao': bem['data_localizacao']
            }
        else:
            logger.warning(f"Bem {numero_bem} não encontrado no banco")
            return None
            
    except Exception as e:
        logger.error(f"Erro ao buscar detalhes do bem {numero_bem}: {str(e)}")
        return None
    
# ==============================
# Rotas Principais
# ==============================
@app.route('/', methods=['GET', 'POST'])
def index():
    """Página inicial do sistema"""
    # Obter mensagem de sucesso se existir
    mensagem_sucesso = request.args.get('mensagem', None)
    
    # Verificar se o banco existe
    if not os.path.exists(DB_PATH):
        mensagem = "Banco de dados não encontrado. Execute a migração do Excel para SQLite antes de usar o sistema."
        logger.warning(mensagem)
        return render_template('index.html', mensagem=mensagem, bem_detalhes=None ,**_carregar_dados_bancos())
    
    # Processar requisição POST
    if request.method == 'POST':
        numero_bem = request.form.get('numero_bem', '').strip()
        localizacao = request.form.get('localizacao', '').strip()
        
        # Validações
        if not numero_bem:
            return render_template('index.html', 
                                 mensagem='Por favor, digite o número do bem.',
                                 **_carregar_dados_bancos())
        
        if not re.match(r'^[A-Za-z0-9-]+$', numero_bem):
            return render_template('index.html',
                                 mensagem='O número do bem deve conter apenas letras, números ou hífen.',
                                 **_carregar_dados_bancos())
        
        # Processar o bem
        resultado = _processar_bem(numero_bem, localizacao)
        return render_template('index.html', 
                             **_carregar_dados_bancos(),
                             **resultado)
    
    # Requisição GET - apenas exibir a página
    return render_template('index.html', 
                         mensagem=None,
                         mensagem_sucesso=mensagem_sucesso,  # Adicionar esta linha
                         show_modal=False,
                         **_carregar_dados_bancos())

@app.route('/visualizar/<tipo>')
def visualizar(tipo: str):
    """Página de visualização de bens com paginação"""
    if not os.path.exists(DB_PATH):
        return render_template('visualizar.html', 
                             titulo='Visualização', 
                             tipo=tipo,
                             paginacao={
                                 'dados': [],
                                 'pagina_atual': 1,
                                 'por_pagina': 200,
                                 'total_registros': 0,
                                 'total_paginas': 0
                             },
                             mensagem="Banco de dados não encontrado.")

    try:
        # Obter parâmetros de paginação
        pagina = request.args.get('pagina', 1, type=int)
        por_pagina = request.args.get('por_pagina', 200, type=int)
        
        # Validar parâmetros
        pagina = max(1, pagina)
        por_pagina = max(50, min(por_pagina, 1000))
        
        # Obter dados paginados
        paginacao = obter_bens_paginados(DB_PATH, tipo, pagina, por_pagina)
        
        # Definir título
        if tipo == 'localizados':
            titulo = 'Bens Localizados'
        elif tipo == 'nao-localizados':
            titulo = 'Bens Não Localizados'
        else:
            titulo = 'Visualização'
            paginacao['dados'] = []
        
        return render_template('visualizar.html', 
                             titulo=titulo,
                             tipo=tipo,
                             paginacao=paginacao)
            
    except Exception as e:
        logger.error(f"Erro em /visualizar/{tipo}: {str(e)}")
        return render_template('visualizar.html', 
                             titulo='Erro',
                             tipo=tipo,
                             paginacao={
                                 'dados': [],
                                 'pagina_atual': 1,
                                 'por_pagina': 200,
                                 'total_registros': 0,
                                 'total_paginas': 0
                             },
                             mensagem=f"Erro ao carregar dados: {str(e)}")

@app.route('/exportar/<tipo>')
def exportar(tipo: str):
    """Exporta relatórios para Excel - versão otimizada"""
    if not os.path.exists(DB_PATH):
        abort(404, description="Banco de dados não encontrado.")

    try:
        # Usar a função paginada mas com limite muito alto para exportar tudo
        resultado = obter_bens_paginados(DB_PATH, tipo, 1, 1000000)
        
        if tipo == 'localizados':
            registros = resultado['dados']
            nome_base = 'bens_localizados'
        elif tipo == 'nao-localizados':
            registros = resultado['dados']
            nome_base = 'bens_nao_localizados'
        else:
            abort(400, description="Tipo inválido.")
            
    except Exception as e:
        logger.error(f"Falha ao preparar dados para exportação: {str(e)}")
        abort(500, description="Erro ao preparar dados para exportação.")

    # Exportar para Excel
    try:
        import pandas as pd
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        out_dir = caminho_relativo("relatorios")
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, f"{nome_base}_{ts}.xlsx")

        df = pd.DataFrame(registros)
        if 'numero' in df.columns:
            df = df.sort_values(by='numero')
        df.to_excel(out_path, index=False)
        
        logger.info(f"Relatório exportado: {out_path} ({len(registros)} registros)")
        return send_file(out_path, as_attachment=True)
        
    except Exception as e:
        logger.error(f"Falha ao exportar Excel: {str(e)}")
        abort(500, description="Erro ao exportar Excel.")

@app.route('/importar-excel', methods=['POST'])
def importar_excel():
    """Rota para importar dados do Excel para o SQLite"""
    try:
        # Verificar se arquivo foi enviado
        if 'excel_file' not in request.files:
            return render_template('index.html', 
                                 mensagem='Nenhum arquivo selecionado',
                                 **_carregar_dados_bancos())
        
        arquivo = request.files['excel_file']
        
        # Verificar se o arquivo tem nome
        if arquivo.filename == '':
            return render_template('index.html',
                                 mensagem='Nenhum arquivo selecionado',
                                 **_carregar_dados_bancos())
        
        # Verificar extensão
        if not arquivo.filename.lower().endswith(('.xlsx', '.xls')):
            return render_template('index.html',
                                 mensagem='Formato de arquivo inválido. Use .xlsx ou .xls',
                                 **_carregar_dados_bancos())
        
        # Salvar arquivo temporariamente
        filename = secure_filename(arquivo.filename)
        temp_path = os.path.join('temp', filename)
        os.makedirs('temp', exist_ok=True)
        arquivo.save(temp_path)
        
        # Obter parâmetros do formulário
        aba_nome = request.form.get('aba_nome', 'Estoque')
        criar_backup = request.form.get('backup') == 'on'
        
        # Primeiro verificar a estrutura
        valido, mensagem_verificacao = verificar_estrutura_excel(temp_path, aba_nome)
        
        if not valido:
            # Mostrar colunas disponíveis para ajudar o usuário
            from utils.excel_importer import obter_colunas_excel
            colunas_disponiveis = obter_colunas_excel(temp_path, aba_nome)
            mensagem_erro = f"{mensagem_verificacao}. Colunas disponíveis: {', '.join(colunas_disponiveis)}"
            
            # Limpar arquivo temporário
            try:
                os.remove(temp_path)
            except:
                pass
            
            return render_template('index.html',
                                 mensagem=mensagem_erro,
                                 **_carregar_dados_bancos())
        
        # Executar importação
        sucesso, mensagem = importar_excel_para_sqlite(
            temp_path, aba_nome, DB_PATH, criar_backup
        )
        
        # Limpar arquivo temporário
        try:
            os.remove(temp_path)
        except:
            pass
        
        # Recarregar dados do banco
        dados_banco = _carregar_dados_bancos()
        
        return render_template('index.html',
                             mensagem=mensagem,
                             show_modal=False,
                             **dados_banco)
        
    except Exception as e:
        logger.error(f"Erro na rota de importação: {str(e)}")
        
        # Limpar arquivo temporário em caso de erro
        try:
            if 'temp_path' in locals():
                os.remove(temp_path)
        except:
            pass
        
        return render_template('index.html',
                             mensagem=f'Erro durante a importação: {str(e)}',
                             **_carregar_dados_bancos())

# ==============================
# Rotas CRUD
# ==============================
@app.route('/api/bem/<numero_bem>')
def api_obter_bem(numero_bem):
    """API para obter dados completos de um bem"""
    try:
        bem = obter_bem_por_numero(DB_PATH, numero_bem)
        
        if bem:
            return jsonify({'success': True, 'data': bem})
        else:
            return jsonify({'success': False, 'message': 'Bem não encontrado'})
            
    except Exception as e:
        logger.error(f"Erro ao obter bem {numero_bem}: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/api/bem/editar', methods=['POST'])
def api_editar_bem():
    """API para editar um bem existente"""
    try:
        dados = request.get_json()
        bem_id = dados.get('bem_id')
        
        sucesso, mensagem = atualizar_bem(DB_PATH, bem_id, dados)
        
        return jsonify({'success': sucesso, 'message': mensagem})
        
    except Exception as e:
        logger.error(f"Erro ao editar bem: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/api/bem/excluir/<int:bem_id>', methods=['DELETE'])
def api_excluir_bem(bem_id):
    """API para excluir um bem"""
    try:
        sucesso, mensagem = excluir_bem(DB_PATH, bem_id)
        
        return jsonify({'success': sucesso, 'message': mensagem})
        
    except Exception as e:
        logger.error(f"Erro ao excluir bem {bem_id}: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/api/bem/novo', methods=['POST'])
def api_novo_bem():
    """API para criar um novo bem"""
    try:
        # Obter dados do formulário
        dados = {
            'numero': request.form.get('numero'),
            'situacao': request.form.get('situacao'),
            'nome': request.form.get('nome'),
            'localizacao': request.form.get('localizacao'),
            'observacoes': request.form.get('observacoes')
        }
        
        # Verificar se número já existe
        from utils.db_handler import verificar_numero_existe
        if verificar_numero_existe(DB_PATH, dados['numero']):
            return jsonify({
                'success': False, 
                'message': 'Já existe um bem com este número!'
            })
        
        # Criar o bem
        sucesso, mensagem = criar_novo_bem(DB_PATH, dados)
        
        if sucesso:
            # Se for sucesso, redirecionar para a página inicial com mensagem
            return redirect(url_for('index', mensagem=mensagem))
        else:
            return jsonify({'success': False, 'message': mensagem})
        
    except Exception as e:
        logger.error(f"Erro ao criar novo bem: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/buscar')
def buscar_bens():
    """Página de busca avançada"""
    termo = request.args.get('q', '')
    
    resultados = buscar_bens_por_nome(DB_PATH, termo) if termo else []
    
    return render_template('buscar.html', 
                         resultados=resultados, 
                         termo_busca=termo,
                         total_resultados=len(resultados))

@app.route('/novo-bem')
def novo_bem():
    """Página para cadastrar novo bem"""
    return render_template('novo_bem.html')

@app.route('/api/verificar-numero', methods=['GET'])
def api_verificar_numero():
    """API para verificar se um número de bem já existe"""
    try:
        numero = request.args.get('numero', '').strip()
        if not numero:
            return jsonify({'exists': False})
        
        from utils.db_handler import verificar_numero_existe
        existe = verificar_numero_existe(DB_PATH, numero)
        
        return jsonify({'exists': existe})
        
    except Exception as e:
        logger.error(f"Erro ao verificar número: {str(e)}")
        return jsonify({'exists': False})



@app.route('/criar-bem', methods=['POST'])
def criar_bem():
    """Rota tradicional para criar novo bem"""
    try:
        dados = {
            'numero': request.form.get('numero', '').strip(),
            'situacao': request.form.get('situacao', 'Pendente'),
            'nome': request.form.get('nome', '').strip(),
            'localizacao': request.form.get('localizacao', '').strip(),
            'observacoes': request.form.get('observacoes', '').strip()
        }
        
        # Validações
        if not dados['numero'] or not dados['nome']:
            return render_template('novo_bem.html', 
                                 erro='Número e nome são obrigatórios',
                                 dados=dados)
        
        if not re.match(r'^[A-Za-z0-9-]+$', dados['numero']):
            return render_template('novo_bem.html',
                                 erro='Número do bem deve conter apenas letras, números ou hífen',
                                 dados=dados)
        
        # Verificar se número já existe
        from utils.db_handler import verificar_numero_existe
        if verificar_numero_existe(DB_PATH, dados['numero']):
            return render_template('novo_bem.html',
                                 erro='Já existe um bem com este número!',
                                 dados=dados)
        
        # Criar o bem
        sucesso, mensagem = criar_novo_bem(DB_PATH, dados)
        
        if sucesso:
            return redirect(url_for('index', mensagem=mensagem))
        else:
            return render_template('novo_bem.html',
                                 erro=mensagem,
                                 dados=dados)
            
    except Exception as e:
        logger.error(f"Erro ao criar bem: {str(e)}")
        return render_template('novo_bem.html',
                             erro=f'Erro interno: {str(e)}',
                             dados=request.form.to_dict())

@app.route('/sair')
def sair():
    """Página de encerramento do aplicativo"""
    return render_template('sair.html', 
                         total_count=_carregar_dados_bancos().get('total_count', 0),
                         session_time="5min")

# ==============================
# Inicialização
# ==============================
if __name__ == '__main__':
    logger.info("Iniciando aplicação Flask")
    app.run(debug=True)