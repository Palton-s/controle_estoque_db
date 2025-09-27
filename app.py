import os
import sys
import re
import sqlite3
import shutil
import io
from datetime import datetime
from typing import Tuple, Dict, Any
from werkzeug.utils import secure_filename
from flask import Flask, render_template, request, send_file, abort, jsonify, redirect, url_for, Response

# Importar handlers
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
    contar_bens,
    obter_bens_paginados,
    obter_localidades,
    obter_bens_por_localidade,
    obter_todos_bens_por_localidade,
    verificar_localidade_existe,
    verificar_numero_existe
)

from utils.excel_importer import importar_excel_para_sqlite, verificar_estrutura_excel
from utils.logger import logger

# ==============================
# Configuração e Inicialização
# ==============================
class Config:
    """Configurações centralizadas da aplicação"""
    DB_PATH = os.path.join(os.path.abspath("."), "relatorios", "controle_patrimonial.db")
    UPLOAD_FOLDER = 'temp'
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB
    PAGINATION_SIZE = 200
    EXPORT_CHUNK_SIZE = 1000

app = Flask(__name__)
app.config.from_object(Config)

# ==============================
# Serviços e Validações
# ==============================
class BemValidator:
    """Serviço de validação de dados de bens"""
    
    @staticmethod
    def validar_numero(numero: str) -> Tuple[bool, str]:
        """Valida o formato do número do bem"""
        if not numero or not numero.strip():
            return False, "Número do bem é obrigatório"
        
        if not re.match(r'^[A-Za-z0-9-]+$', numero.strip()):
            return False, "O número do bem deve conter apenas letras, números ou hífen"
        
        return True, ""
    
    @staticmethod
    def validar_dados_criacao(dados: Dict[str, Any]) -> Tuple[bool, str]:
        """Valida dados para criação de bem"""
        if not dados.get('numero') or not dados['numero'].strip():
            return False, "Número do bem é obrigatório"
        
        if not dados.get('nome') or not dados['nome'].strip():
            return False, "Nome do bem é obrigatório"
        
        return BemValidator.validar_numero(dados['numero'])

class BemService:
    """Serviço centralizado para operações com bens"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
    
   
    def processar_localizacao(self, numero_bem: str, localizacao: str = None) -> Dict[str, Any]:
        """Processa a localização de um bem - VERSÃO CORRIGIDA"""
        try:
            # Se localização não foi informada, tenta completar do banco
            if not localizacao:
                localizacao = buscar_localizacao_existente(numero_bem, self.db_path)
            
            # Verifica se o bem existe
            encontrado, erro = verificar_bem(numero_bem, self.db_path)
            if not encontrado:
                return {
                    'mensagem': erro or 'Bem não encontrado.',
                    'bem_detalhes': None,
                    'localizacao_informada': localizacao,
                    'show_modal': True  # ← CORREÇÃO: Manter show_modal
                }
            
            # Marca como localizado
            mensagem = marcar_bem_localizado(numero_bem, self.db_path, localizacao)
            bem_detalhes = self._obter_detalhes_bem(numero_bem, localizacao)
            
            return {
                'mensagem': mensagem,
                'bem_detalhes': bem_detalhes,
                'localizacao_informada': localizacao,
                'show_modal': True  # ← CORREÇÃO: Manter show_modal
            }
            
        except Exception as e:
            logger.error(f"Erro ao processar bem {numero_bem}: {str(e)}")
            return {
                'mensagem': 'Erro interno ao processar o bem.',
                'bem_detalhes': None,
                'localizacao_informada': localizacao,
                'show_modal': True  # ← CORREÇÃO: Manter show_modal
            }
    
    def _obter_detalhes_bem(self, numero_bem: str, localizacao: str = None) -> Dict[str, Any]:
        """Busca detalhes de um bem específico"""
        try:
            bem = obter_bem_por_numero(self.db_path, numero_bem)
            
            if bem:
                localizacao_final = localizacao or bem['localizacao'] or 'Não informada'
                
                return {
                    'id': bem['id'],
                    'nome': bem['nome'] or 'Não informado',
                    'numero': bem['numero'] or 'Não informado',
                    'situacao': bem['situacao'] or 'Pendente',
                    'localizacao': localizacao_final,
                    'data_criacao': bem['data_criacao'],
                    'data_localizacao': bem['data_localizacao']
                }
            
            return None
            
        except Exception as e:
            logger.error(f"Erro ao buscar detalhes do bem {numero_bem}: {str(e)}")
            return None
    
    def criar_bem(self, dados: Dict[str, Any]) -> Tuple[bool, str]:
        """Cria um novo bem no sistema"""
        try:
            # Validação básica
            valido, mensagem = BemValidator.validar_dados_criacao(dados)
            if not valido:
                return False, mensagem
            
            # Verificar duplicidade
            if verificar_numero_existe(self.db_path, dados['numero']):
                return False, "Já existe um bem com este número!"
            
            # Dados padrão
            dados_completos = {
                'numero': dados['numero'].strip(),
                'nome': dados['nome'].strip(),
                'situacao': dados.get('situacao', 'Pendente'),
                'localizacao': dados.get('localizacao', '').strip(),
                'observacoes': dados.get('observacoes', '').strip()
            }
            
            return criar_novo_bem(self.db_path, dados_completos)
            
        except Exception as e:
            logger.error(f"Erro ao criar bem: {str(e)}")
            return False, f"Erro interno: {str(e)}"

class ExportService:
    """Serviço para exportação de dados"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
    
    def exportar_bens_por_tipo(self, tipo: str) -> Response:
        """Exporta bens por tipo com streaming para grandes volumes"""
        try:
            import pandas as pd
            
            # Obter todos os dados de uma vez (otimizado para volumes razoáveis)
            if tipo == 'localizados':
                resultado = obter_bens_paginados(self.db_path, tipo, 1, 100000)
                nome_arquivo = 'bens_localizados'
            elif tipo == 'nao-localizados':
                resultado = obter_bens_paginados(self.db_path, tipo, 1, 100000)
                nome_arquivo = 'bens_nao_localizados'
            else:
                abort(400, description="Tipo inválido")
            
            registros = resultado['dados']
            if not registros:
                abort(404, description="Nenhum dado encontrado para exportação")
            
            # Criar arquivo Excel
            df = pd.DataFrame(registros)
            if 'numero' in df.columns:
                df = df.sort_values(by='numero')
            
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            caminho_arquivo = os.path.join(
                os.path.dirname(self.db_path), 
                f"{nome_arquivo}_{timestamp}.xlsx"
            )
            
            df.to_excel(caminho_arquivo, index=False)
            logger.info(f"Relatório exportado: {caminho_arquivo} ({len(registros)} registros)")
            
            return send_file(caminho_arquivo, as_attachment=True)
            
        except ImportError:
            abort(500, description="Pandas não está instalado")
        except Exception as e:
            logger.error(f"Erro na exportação: {str(e)}")
            abort(500, description="Erro ao exportar dados")
    
    def exportar_localidade(self, localidade: str) -> Any:
        """Exporta bens por localidade"""
        try:
            import pandas as pd
            
            registros = obter_todos_bens_por_localidade(self.db_path, localidade)
            
            if not registros:
                abort(404, description=f"Nenhum bem encontrado para a localidade: {localidade}")
            
            df = pd.DataFrame(registros)
            if 'numero' in df.columns:
                df = df.sort_values(by='numero')
            
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            nome_seguro = re.sub(r'[^\w\s-]', '', localidade).strip().lower()
            nome_seguro = re.sub(r'[-\s]+', '_', nome_seguro)
            
            caminho_arquivo = os.path.join(
                os.path.dirname(self.db_path),
                f"bens_localidade_{nome_seguro}_{timestamp}.xlsx"
            )
            
            df.to_excel(caminho_arquivo, index=False)
            logger.info(f"Relatório por localidade exportado: {caminho_arquivo}")
            
            return send_file(caminho_arquivo, as_attachment=True)
            
        except Exception as e:
            logger.error(f"Erro ao exportar localidade: {str(e)}")
            abort(500, description="Erro ao exportar dados da localidade")

# ==============================
# Inicialização de Serviços
# ==============================
def caminho_relativo(pasta: str) -> str:
    """Retorna caminho absoluto, mesmo empacotado com PyInstaller"""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, pasta)
    return os.path.join(os.path.abspath("."), pasta)

# Configurar caminho do banco
DB_PATH = app.config['DB_PATH']
bem_service = BemService(DB_PATH)
export_service = ExportService(DB_PATH)

# ==============================
# Middleware e Validações Globais
# ==============================
@app.before_request
def validar_banco_dados():
    """Middleware para verificar se o banco existe antes de rotas críticas"""
    rotas_criticas = ['index', 'visualizar', 'exportar', 'relatorio_localidades', 'buscar_bens']
    
    if request.endpoint in rotas_criticas:
        if not os.path.exists(DB_PATH):
            if request.endpoint and request.endpoint.startswith('api_'):
                abort(503, description="Banco de dados não disponível")

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
# Funções Auxiliares
# ==============================
def carregar_dados_bancos() -> Dict[str, int]:
    """Carrega contagens do banco de forma otimizada"""
    try:
        contagens = contar_bens(DB_PATH)
        return {
            'localizados_count': contagens['localizados'],
            'nao_localizados_count': contagens['nao_localizados'],
            'total_count': contagens['total']
        }
    except Exception as e:
        logger.error(f"Erro ao carregar contagens do banco: {str(e)}")
        return {'localizados_count': 0, 'nao_localizados_count': 0, 'total_count': 0}

# ==============================
# Rotas Principais
# ==============================
@app.route('/', methods=['GET', 'POST'])
def index():
    """Página inicial do sistema"""
    mensagem_sucesso = request.args.get('mensagem', None)
    
    # Verificar se o banco existe
    if not os.path.exists(DB_PATH):
        mensagem = "Banco de dados não encontrado. Execute a migração do Excel para SQLite antes de usar o sistema."
        logger.warning(mensagem)
        return render_template('index.html', 
                             mensagem=mensagem, 
                             bem_detalhes=None,
                             **carregar_dados_bancos())
    
    # Processar requisição POST
    if request.method == 'POST':
        numero_bem = request.form.get('numero_bem', '').strip()
        localizacao = request.form.get('localizacao', '').strip()
        
        # Validação do número do bem
        valido, mensagem_validacao = BemValidator.validar_numero(numero_bem)
        if not valido:
            return render_template('index.html', 
                                 mensagem=mensagem_validacao,
                                 **carregar_dados_bancos())
        
        # Processar o bem
        resultado = bem_service.processar_localizacao(numero_bem, localizacao)
        return render_template('index.html', 
                             **carregar_dados_bancos(),
                             **resultado)
    
    # Requisição GET
    return render_template('index.html', 
                         mensagem=None,
                         mensagem_sucesso=mensagem_sucesso,
                         show_modal=False,
                         **carregar_dados_bancos())

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
                                 'por_pagina': app.config['PAGINATION_SIZE'],
                                 'total_registros': 0,
                                 'total_paginas': 0
                             },
                             mensagem="Banco de dados não encontrado.")

    try:
        # Obter parâmetros de paginação
        pagina = max(1, request.args.get('pagina', 1, type=int))
        por_pagina = max(50, min(
            request.args.get('por_pagina', app.config['PAGINATION_SIZE'], type=int), 
            1000
        ))
        
        # Obter dados paginados
        paginacao = obter_bens_paginados(DB_PATH, tipo, pagina, por_pagina)
        
        # Definir título
        titulos = {
            'localizados': 'Bens Localizados',
            'nao-localizados': 'Bens Não Localizados'
        }
        titulo = titulos.get(tipo, 'Visualização')
        
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
                                 'por_pagina': app.config['PAGINATION_SIZE'],
                                 'total_registros': 0,
                                 'total_paginas': 0
                             },
                             mensagem=f"Erro ao carregar dados: {str(e)}")

@app.route('/exportar/<tipo>')
def exportar(tipo: str):
    """Exporta relatórios para Excel"""
    if not os.path.exists(DB_PATH):
        abort(404, description="Banco de dados não encontrado.")
    
    if tipo not in ['localizados', 'nao-localizados']:
        abort(400, description="Tipo inválido.")
    
    return export_service.exportar_bens_por_tipo(tipo)

@app.route('/exportar-localidade/<localidade>')
def exportar_localidade(localidade: str):
    """Exporta relatório por localidade para Excel"""
    if not os.path.exists(DB_PATH):
        abort(404, description="Banco de dados não encontrado.")
    
    return export_service.exportar_localidade(localidade)

@app.route('/importar-excel', methods=['POST'])
def importar_excel():
    """Rota para importar dados do Excel para o SQLite"""
    try:
        # Verificar se arquivo foi enviado
        if 'excel_file' not in request.files:
            return render_template('index.html', 
                                 mensagem='Nenhum arquivo selecionado',
                                 **carregar_dados_bancos())
        
        arquivo = request.files['excel_file']
        
        if arquivo.filename == '':
            return render_template('index.html',
                                 mensagem='Nenhum arquivo selecionado',
                                 **carregar_dados_bancos())
        
        # Verificar extensão
        if not arquivo.filename.lower().endswith(('.xlsx', '.xls')):
            return render_template('index.html',
                                 mensagem='Formato de arquivo inválido. Use .xlsx ou .xls',
                                 **carregar_dados_bancos())
        
        # Salvar arquivo temporariamente
        filename = secure_filename(arquivo.filename)
        temp_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
        arquivo.save(temp_path)
        
        # Obter parâmetros
        aba_nome = request.form.get('aba_nome', 'Estoque')
        criar_backup = request.form.get('backup') == 'on'
        
        # Verificar estrutura
        valido, mensagem_verificacao = verificar_estrutura_excel(temp_path, aba_nome)
        
        if not valido:
            from utils.excel_importer import obter_colunas_excel
            colunas_disponiveis = obter_colunas_excel(temp_path, aba_nome)
            mensagem_erro = f"{mensagem_verificacao}. Colunas disponíveis: {', '.join(colunas_disponiveis)}"
            
            try:
                os.remove(temp_path)
            except:
                pass
            
            return render_template('index.html',
                                 mensagem=mensagem_erro,
                                 **carregar_dados_bancos())
        
        # Executar importação
        sucesso, mensagem = importar_excel_para_sqlite(
            temp_path, aba_nome, DB_PATH, criar_backup
        )
        
        # Limpar arquivo temporário
        try:
            os.remove(temp_path)
        except:
            pass
        
        return render_template('index.html',
                             mensagem=mensagem,
                             show_modal=False,
                             **carregar_dados_bancos())
        
    except Exception as e:
        logger.error(f"Erro na importação: {str(e)}")
        
        try:
            if 'temp_path' in locals():
                os.remove(temp_path)
        except:
            pass
        
        return render_template('index.html',
                             mensagem=f'Erro durante a importação: {str(e)}',
                             **carregar_dados_bancos())

# ==============================
# Rotas CRUD Unificadas
# ==============================
@app.route('/api/bens', methods=['POST'])
def api_criar_bem():
    """API unificada para criar bem (JSON e Form)"""
    try:
        # Obter dados conforme o tipo de requisição
        if request.is_json:
            dados = request.get_json()
        else:
            dados = request.form.to_dict()
        
        # Criar bem
        sucesso, mensagem = bem_service.criar_bem(dados)
        
        # Retorno adaptável ao tipo de requisição
        if request.is_json:
            return jsonify({'success': sucesso, 'message': mensagem})
        else:
            if sucesso:
                return redirect(url_for('index', mensagem=mensagem))
            else:
                return render_template('novo_bem.html',
                                     erro=mensagem,
                                     dados=dados)
        
    except Exception as e:
        logger.error(f"Erro ao criar bem: {str(e)}")
        
        if request.is_json:
            return jsonify({'success': False, 'message': str(e)})
        else:
            return render_template('novo_bem.html',
                                 erro=f'Erro interno: {str(e)}',
                                 dados=request.form.to_dict())

@app.route('/api/bens/<numero_bem>')
def api_obter_bem(numero_bem):
    """API para obter dados de um bem"""
    try:
        bem = obter_bem_por_numero(DB_PATH, numero_bem)
        
        if bem:
            return jsonify({'success': True, 'data': bem})
        else:
            return jsonify({'success': False, 'message': 'Bem não encontrado'})
            
    except Exception as e:
        logger.error(f"Erro ao obter bem {numero_bem}: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/api/bens/<int:bem_id>', methods=['PUT'])
def api_editar_bem(bem_id):
    """API para editar um bem existente"""
    try:
        dados = request.get_json()
        sucesso, mensagem = atualizar_bem(DB_PATH, bem_id, dados)
        return jsonify({'success': sucesso, 'message': mensagem})
        
    except Exception as e:
        logger.error(f"Erro ao editar bem: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/api/bens/<int:bem_id>', methods=['DELETE'])
def api_excluir_bem(bem_id):
    """API para excluir um bem"""
    try:
        sucesso, mensagem = excluir_bem(DB_PATH, bem_id)
        return jsonify({'success': sucesso, 'message': mensagem})
        
    except Exception as e:
        logger.error(f"Erro ao excluir bem {bem_id}: {str(e)}")
        return jsonify({'success': False, 'message': str(e)})

@app.route('/api/verificar-numero', methods=['GET'])
def api_verificar_numero():
    """API para verificar se um número de bem já existe"""
    try:
        numero = request.args.get('numero', '').strip()
        if not numero:
            return jsonify({'exists': False})
        
        existe = verificar_numero_existe(DB_PATH, numero)
        return jsonify({'exists': existe})
        
    except Exception as e:
        logger.error(f"Erro ao verificar número: {str(e)}")
        return jsonify({'exists': False})

# ==============================
# Rotas de Interface
# ==============================
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

@app.route('/relatorio/localidades')
def relatorio_localidades():
    """Relatório de bens por localidade - COM FILTROS AVANÇADOS"""
    try:
        localidade_selecionada = request.args.get('localidade', '').strip()
        situacao_filtro = request.args.get('situacao', 'OK')  # Novo filtro
        pagina = request.args.get('pagina', 1, type=int)
        por_pagina = request.args.get('por_pagina', 20, type=int)
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Buscar localidades distintas (com filtro de situação)
        cursor.execute(f'''
            SELECT DISTINCT localizacao 
            FROM bens 
            WHERE localizacao IS NOT NULL 
            AND localizacao != '' 
            AND localizacao != 'Não informada'
            AND situacao = ?
            ORDER BY localizacao
        ''', (situacao_filtro,))
        localidades = [row[0] for row in cursor.fetchall()]
        
        paginacao = None
        
        if localidade_selecionada:
            # Query com filtro de situação
            cursor.execute('''
                SELECT COUNT(*) FROM bens 
                WHERE localizacao = ? AND situacao = ?
            ''', (localidade_selecionada, situacao_filtro))
            total_registros = cursor.fetchone()[0]
            
            offset = (pagina - 1) * por_pagina
            total_paginas = (total_registros + por_pagina - 1) // por_pagina
            
            cursor.execute('''
                SELECT 
                    numero, nome, situacao, localizacao,
                    data_criacao, data_localizacao
                FROM bens 
                WHERE localizacao = ? AND situacao = ?
                ORDER BY numero
                LIMIT ? OFFSET ?
            ''', (localidade_selecionada, situacao_filtro, por_pagina, offset))
            
            bens = []
            for row in cursor.fetchall():
                bens.append({
                    'numero': row[0],
                    'nome': row[1],
                    'situacao': row[2],
                    'localizacao': row[3],
                    'data_criacao': row[4],
                    'data_localizacao': row[5]
                })
            
            paginacao = {
                'dados': bens,
                'pagina_atual': pagina,
                'por_pagina': por_pagina,
                'total_registros': total_registros,
                'total_paginas': total_paginas,
                'situacao_filtro': situacao_filtro  # Para usar no template
            }
        
        conn.close()
        
        return render_template('relatorio_localidades.html',
                             localidades=localidades,
                             localidade_selecionada=localidade_selecionada,
                             paginacao=paginacao)
        
    except Exception as e:
        logger.error(f"Erro no relatório de localidades: {str(e)}")
        return render_template('relatorio_localidades.html',
                             mensagem=f"Erro ao gerar relatório: {str(e)}",
                             localidades=[],
                             localidade_selecionada='',
                             paginacao=None)
@app.route('/sair')
def sair():
    """Página de encerramento do aplicativo"""
    return render_template('sair.html', 
                         total_count=carregar_dados_bancos().get('total_count', 0),
                         session_time="5min")

# ==============================
# Handlers de Erro Globais
# ==============================
@app.errorhandler(404)
def not_found(error):
    if request.path.startswith('/api/'):
        return jsonify({'success': False, 'message': 'Recurso não encontrado'}), 404
    return render_template('404.html'), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Erro interno: {error}")
    if request.path.startswith('/api/'):
        return jsonify({'success': False, 'message': 'Erro interno do servidor'}), 500
    return render_template('500.html'), 500

@app.errorhandler(503)
def service_unavailable(error):
    if request.path.startswith('/api/'):
        return jsonify({'success': False, 'message': 'Serviço temporariamente indisponível'}), 503
    return render_template('503.html'), 503

# ==============================
# Função para Remover Rotas de Debug (Opcional)
# ==============================
def remover_rotas_debug():
    """Remove rotas de debug em produção - opcional"""
    if not app.debug:
        # Em vez de modificar as regras diretamente, simplesmente não registramos as rotas de debug
        # Ou podemos usar condicionais no registro das rotas
        pass

# ==============================
# Rotas de Debug (Apenas em modo desenvolvimento)
# ==============================
if app.debug:
    @app.route('/debug-localidades')
    def debug_localidades():
        """Página de debug para verificar localidades (apenas em desenvolvimento)"""
        from utils.db_handler import debug_localidades_completas
        try:
            resultados = debug_localidades_completas(DB_PATH)
            return render_template('debug_localidades.html', resultados=resultados)
        except Exception as e:
            return f"Erro no debug: {str(e)}"

    @app.route('/teste-consulta-direta/<localidade>')
    def teste_consulta_direta(localidade):
        """Teste de consulta direta no banco (apenas em desenvolvimento)"""
        try:
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            
            cursor.execute(
                "SELECT COUNT(*) as count_exato FROM bens WHERE localizacao = ?",
                (localidade,)
            )
            count_exato = cursor.fetchone()[0]
            
            cursor.execute(
                "SELECT COUNT(*) as count_like FROM bens WHERE localizacao LIKE ?",
                (f"%{localidade}%",)
            )
            count_like = cursor.fetchone()[0]
            
            cursor.execute(
                "SELECT numero, nome, localizacao FROM bens WHERE localizacao = ? LIMIT 5",
                (localidade,)
            )
            exemplos = cursor.fetchall()
            
            conn.close()
            
            return jsonify({
                'localidade': localidade,
                'count_exato': count_exato,
                'count_like': count_like,
                'exemplos': exemplos
            })
            
        except Exception as e:
            return jsonify({'error': str(e)})

# ==============================
# Inicialização
# ==============================
if __name__ == '__main__':
    logger.info("Iniciando aplicação Flask")
    
    # Criar diretórios necessários
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
    
    app.run(debug=True)