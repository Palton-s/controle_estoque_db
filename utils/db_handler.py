import sqlite3
from typing import List, Dict, Tuple, Optional
from contextlib import contextmanager
from utils.logger import logger
# NO INÍCIO DO db_handler.py - ADICIONE ESTA LINHA:
from typing import Any, Dict, Tuple, Optional

# Adicionar após as importações
def criar_tabela_atualizada(db_path: str):
    """Cria a tabela bens com a nova estrutura"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS bens (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    numero TEXT UNIQUE NOT NULL,
                    nome TEXT NOT NULL,
                    situacao TEXT DEFAULT 'Pendente',
                    localizacao TEXT,
                    responsavel TEXT,
                    data_ultima_vistoria DATE,
                    data_vistoria_atual DATE,
                    auditor TEXT,
                    observacoes TEXT,
                    data_criacao DATETIME DEFAULT CURRENT_TIMESTAMP,
                    data_localizacao DATETIME
                )
            ''')
            conn.commit()
            logger.info("Tabela bens criada/atualizada com sucesso")
    except Exception as e:
        logger.error(f"Erro ao criar tabela: {str(e)}")


@contextmanager
def get_db_connection(db_path: str):
    """
    Gerenciador de contexto para conexões com o banco de dados
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row  # Para retornar dicionários
    try:
        yield conn
    finally:
        conn.close()

def verificar_bem(numero_bem: str, db_path: str) -> Tuple[bool, Optional[str]]:
    """Verifica se um bem existe no banco de dados"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM bens WHERE numero = ?", (numero_bem,))
            existe = cursor.fetchone()[0] > 0
            
            logger.info(f"Verificação do bem {numero_bem}: {'Encontrado' if existe else 'Não encontrado'}")
            return existe, None if existe else "Bem não encontrado"
            
    except Exception as e:
        logger.error(f"Erro ao verificar bem {numero_bem}: {str(e)}")
        return False, f"Erro ao verificar bem: {str(e)}"

def marcar_bem_localizado(numero_bem: str, db_path: str, localizacao: Optional[str] = None) -> str:
    """Marca um bem como localizado no banco de dados"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            # Verificar se o bem existe primeiro
            cursor.execute("SELECT COUNT(*) FROM bens WHERE numero = ?", (numero_bem,))
            if cursor.fetchone()[0] == 0:
                return f"Bem {numero_bem} não encontrado no banco de dados"
            
            # Atualizar a situação e localização
            if localizacao:
                cursor.execute("""
                    UPDATE bens 
                    SET situacao = 'OK', localizacao = ?, data_localizacao = datetime('now')
                    WHERE numero = ?
                """, (localizacao, numero_bem))
                mensagem = f"✅ Bem {numero_bem} marcado como localizado em '{localizacao}'!"
            else:
                cursor.execute("""
                    UPDATE bens 
                    SET situacao = 'OK', data_localizacao = datetime('now')
                    WHERE numero = ?
                """, (numero_bem,))
                mensagem = f"✅ Bem {numero_bem} marcado como localizado!"
            
            conn.commit()
            logger.info(mensagem)
            return mensagem
            
    except Exception as e:
        error_msg = f"Erro ao marcar bem {numero_bem} como localizado: {str(e)}"
        logger.error(error_msg)
        return error_msg

def buscar_localizacao_existente(numero_bem: str, db_path: str) -> Optional[str]:
    """Busca a localização atual de um bem no banco de dados"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT localizacao FROM bens WHERE numero = ?", (numero_bem,))
            resultado = cursor.fetchone()
            
            localizacao = resultado['localizacao'] if resultado and resultado['localizacao'] else None
            logger.info(f"Localização do bem {numero_bem}: {localizacao or 'Não definida'}")
            return localizacao
            
    except Exception as e:
        logger.error(f"Erro ao buscar localização do bem {numero_bem}: {str(e)}")
        return None

def verificar_numero_existe(db_path, numero_bem):
    """Verifica se já existe um bem com o número informado"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM bens WHERE numero = ?", (numero_bem,))
            resultado = cursor.fetchone()
            return resultado[0] > 0 if resultado else False
        
    except Exception as e:
        logger.error(f"Erro ao verificar número do bem: {str(e)}")
        return False

def gerar_planilhas_localizacao(db_path: str) -> Tuple[List[Dict], List[Dict]]:
    """Gera listas de bens localizados e não localizados a partir do banco"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            # Buscar bens localizados (situacao = 'OK')
            cursor.execute("SELECT nome, numero, situacao, localizacao FROM bens WHERE situacao = 'OK'")
            localizados = [dict(row) for row in cursor.fetchall()]
            
            # Buscar bens não localizados (situacao != 'OK' ou NULL)
            cursor.execute("SELECT nome, numero, situacao, localizacao FROM bens WHERE situacao != 'OK' OR situacao IS NULL")
            nao_localizados = [dict(row) for row in cursor.fetchall()]
            
            logger.info(f"Geradas listas: {len(localizados)} localizados, {len(nao_localizados)} não localizados")
            return localizados, nao_localizados
            
    except Exception as e:
        logger.error(f"Erro ao gerar planilhas de localização: {str(e)}")
        return [], []

def obter_bens_paginados(db_path: str, tipo: str, pagina: int = 1, por_pagina: int = 200):
    """Obtém bens com paginação incluindo novos campos"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            # Calcular offset
            offset = (pagina - 1) * por_pagina
            
            # Query base atualizada
            if tipo == 'localizados':
                query = """
                    SELECT numero, nome, situacao, localizacao, responsavel,
                           data_ultima_vistoria, data_vistoria_atual, auditor
                    FROM bens WHERE situacao = 'OK'
                """
            elif tipo == 'nao-localizados':
                query = """
                    SELECT numero, nome, situacao, localizacao, responsavel,
                           data_ultima_vistoria, data_vistoria_atual, auditor
                    FROM bens WHERE situacao != 'OK' OR situacao IS NULL
                """
            else:
                query = """
                    SELECT numero, nome, situacao, localizacao, responsavel,
                           data_ultima_vistoria, data_vistoria_atual, auditor
                    FROM bens
                """
            
            # Query com paginação
            query_paginada = f"{query} LIMIT {por_pagina} OFFSET {offset}"
            
            cursor.execute(query_paginada)
            dados = [dict(row) for row in cursor.fetchall()]
            
            # Obter total de registros
            cursor.execute(f"SELECT COUNT(*) FROM ({query})")
            total_registros = cursor.fetchone()[0]
            
            # Calcular total de páginas
            total_paginas = (total_registros + por_pagina - 1) // por_pagina
            
            return {
                'dados': dados,
                'pagina_atual': pagina,
                'por_pagina': por_pagina,
                'total_registros': total_registros,
                'total_paginas': total_paginas
            }
            
    except Exception as e:
        logger.error(f"Erro ao obter bens paginados: {str(e)}")
        return {
            'dados': [],
            'pagina_atual': 1,
            'por_pagina': por_pagina,
            'total_registros': 0,
            'total_paginas': 0
        }
def contar_bens(db_path: str):
    """Retorna contagem total de bens por situação"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT 
                    COUNT(*) as total,
                    SUM(CASE WHEN situacao = 'OK' THEN 1 ELSE 0 END) as localizados,
                    SUM(CASE WHEN situacao != 'OK' OR situacao IS NULL THEN 1 ELSE 0 END) as nao_localizados
                FROM bens
            """)
            
            resultado = cursor.fetchone()
            return {
                'total': resultado['total'],
                'localizados': resultado['localizados'],
                'nao_localizados': resultado['nao_localizados']
            }

         
    except Exception as e:
        logger.error(f"Erro ao contar bens: {str(e)}")
        return {'total': 0, 'localizados': 0, 'nao_localizados': 0}
    
    
def obter_bem_por_numero(db_path: str, numero_bem: str):
    """Obtém todos os dados de um bem específico com nova estrutura"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, numero, nome, localizacao, situacao, responsavel,
                       data_ultima_vistoria, data_vistoria_atual, auditor,
                       data_criacao, data_localizacao, observacoes
                FROM bens WHERE numero = ?
            """, (numero_bem,))
            
            resultado = cursor.fetchone()
            return dict(resultado) if resultado else None
            
    except Exception as e:
        logger.error(f"Erro ao obter bem {numero_bem}: {str(e)}")
        return None

def atualizar_bem(db_path: str, bem_id: int, dados: dict):
    """Atualiza os dados de um bem"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE bens 
                SET nome = ?, localizacao = ?, situacao = ?
                WHERE id = ?
            """, (dados['nome'], dados['localizacao'], dados['situacao'], bem_id))
            
            conn.commit()
            logger.info(f"Bem {bem_id} atualizado com sucesso")
            return True, "✅ Bem atualizado com sucesso!"
            
    except Exception as e:
        logger.error(f"Erro ao atualizar bem {bem_id}: {str(e)}")
        return False, f"❌ Erro ao atualizar bem: {str(e)}"

def criar_novo_bem(db_path: str, dados: dict):
    """Cria um novo bem no sistema"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            # Verificar se já existe
            cursor.execute("SELECT COUNT(*) FROM bens WHERE numero = ?", (dados['numero'],))
            if cursor.fetchone()[0] > 0:
                return False, "❌ Já existe um bem com este número!"
            
            # Inserir novo registro
            cursor.execute("""
                INSERT INTO bens (numero, nome, localizacao, situacao, data_criacao)
                VALUES (?, ?, ?, ?, datetime('now'))
            """, (dados['numero'], dados['nome'], dados['localizacao'], dados['situacao']))
            
            conn.commit()
            logger.info(f"Novo bem criado: {dados['numero']} - {dados['nome']}")
            return True, "✅ Bem cadastrado com sucesso!"
            
    except sqlite3.IntegrityError:
        return False, "❌ Erro: Já existe um bem com este número!"
    except Exception as e:
        logger.error(f"Erro ao criar novo bem: {str(e)}")
        return False, f"❌ Erro ao criar bem: {str(e)}"

def excluir_bem(db_path: str, bem_id: int):
    """Exclui um bem do sistema"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT numero FROM bens WHERE id = ?", (bem_id,))
            bem = cursor.fetchone()
            
            cursor.execute("DELETE FROM bens WHERE id = ?", (bem_id,))
            conn.commit()
            
            logger.info(f"Bem {bem['numero']} excluído")
            return True, f"✅ Bem {bem['numero']} excluído com sucesso!"
            
    except Exception as e:
        logger.error(f"Erro ao excluir bem {bem_id}: {str(e)}")
        return False, f"❌ Erro ao excluir bem: {str(e)}"

def buscar_bens_por_nome(db_path: str, termo_busca: str):
    """Busca bens por nome ou descrição"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, numero, nome, localizacao, situacao
                FROM bens 
                WHERE nome LIKE ? OR numero LIKE ?
                ORDER BY nome
            """, (f'%{termo_busca}%', f'%{termo_busca}%'))
            
            return [dict(row) for row in cursor.fetchall()]
            
    except Exception as e:
        logger.error(f"Erro na busca por '{termo_busca}': {str(e)}")
        return []
    

def obter_localidades(db_path: str) -> list:
    """Obtém todas as localidades distintas do banco de dados"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute(
                "SELECT DISTINCT localizacao FROM bens WHERE localizacao IS NOT NULL AND TRIM(localizacao) != '' ORDER BY localizacao"
            )
            
            localidades = [row['localizacao'] for row in cursor.fetchall() if row['localizacao'] and row['localizacao'].strip()]
            return localidades
    except Exception as e:
        logger.error(f"Erro ao obter localidades: {str(e)}")
        return []

def obter_bens_por_localidade(db_path: str, localidade: str, pagina: int = 1, por_pagina: int = 200) -> dict:
    """Obtém bens paginados por localidade - VERSÃO CORRIGIDA"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            # Calcular offset
            offset = (pagina - 1) * por_pagina
            
            # Query principal com paginação
            cursor.execute("""
                SELECT id, numero, nome, situacao, localizacao, observacoes,
                       data_criacao, data_localizacao 
                FROM bens 
                WHERE localizacao = ?
                ORDER BY numero
                LIMIT ? OFFSET ?
            """, (localidade, por_pagina, offset))
            
            # Obter colunas
            colunas = [desc[0] for desc in cursor.description]
            dados = [dict(zip(colunas, row)) for row in cursor.fetchall()]
            
            # Obter total de registros
            cursor.execute("SELECT COUNT(*) FROM bens WHERE localizacao = ?", (localidade,))
            total_registros = cursor.fetchone()[0]
            
            # Calcular total de páginas
            total_paginas = (total_registros + por_pagina - 1) // por_pagina if por_pagina > 0 else 1
            
            return {
                'dados': dados,
                'pagina_atual': pagina,
                'por_pagina': por_pagina,
                'total_registros': total_registros,
                'total_paginas': total_paginas,
                'localidade': localidade
            }
            
    except Exception as e:
        logger.error(f"Erro ao obter bens por localidade: {str(e)}")
        return {
            'dados': [],
            'pagina_atual': 1,
            'por_pagina': por_pagina,
            'total_registros': 0,
            'total_paginas': 1,
            'localidade': localidade
        }

def obter_todos_bens_por_localidade(db_path: str, localidade: str) -> list:
    """Obtém todos os bens de uma localidade"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, numero, nome, situacao, localizacao, observacoes, 
                       data_criacao, data_localizacao 
                FROM bens 
                WHERE localizacao = ?
                ORDER BY numero
            """, (localidade,))
            
            colunas = [desc[0] for desc in cursor.description]
            registros = [dict(zip(colunas, row)) for row in cursor.fetchall()]
            
            return registros
        
    except Exception as e:
        logger.error(f"Erro ao obter todos os bens por localidade: {str(e)}")
        return []

def verificar_localidade_existe(db_path: str, localidade: str) -> bool:
    """Verifica se uma localidade existe no banco - VERSÃO CORRIGIDA"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute(
                "SELECT COUNT(*) FROM bens WHERE localizacao = ?",
                (localidade,)
            )
            
            count = cursor.fetchone()[0]
            return count > 0
    except Exception as e:
        logger.error(f"Erro ao verificar localidade: {str(e)}")
        return False

# Funções de debug (mantidas para compatibilidade)
def debug_localidades_completas(db_path: str) -> list:
    """Debug completo das localidades"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT localizacao, COUNT(*) as quantidade 
                FROM bens 
                WHERE localizacao IS NOT NULL AND TRIM(localizacao) != ''
                GROUP BY localizacao 
                ORDER BY localizacao
            """)
            
            resultados = []
            for row in cursor.fetchall():
                localidade, quantidade = row['localizacao'], row['quantidade']
                if localidade and localidade.strip():
                    resultados.append({
                        'localidade': localidade,
                        'quantidade': quantidade
                    })
            
            return resultados
        
    except Exception as e:
        logger.error(f"Erro no debug de localidades: {str(e)}")
        return []

def diagnosticar_localidade(db_path: str, localidade: str):
    """Faz diagnóstico completo de uma localidade"""
    try:
        with get_db_connection(db_path) as conn:
            cursor = conn.cursor()
            
            resultados = {}
            
            # 1. Busca exata
            cursor.execute(
                "SELECT COUNT(*), GROUP_CONCAT(numero) FROM bens WHERE localizacao = ?",
                (localidade,)
            )
            count_exato, numeros_exato = cursor.fetchone()
            resultados['busca_exata'] = {
                'count': count_exato,
                'numeros': numeros_exato.split(',') if numeros_exato else []
            }
            
            return resultados
        
    except Exception as e:
        logger.error(f"Erro no diagnóstico: {str(e)}")
        return {'error': str(e)}
    
# ==============================
# FUNÇÕES CRUD ADICIONAIS - ADICIONE ESTE BLOCO NO FINAL DO db_handler.py
# ==============================

def atualizar_bem(db_path: str, bem_id: int, dados: Dict[str, Any]) -> Tuple[bool, str]:
    """Atualiza um bem existente no banco de dados"""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Construir query dinamicamente baseada nos campos fornecidos
        campos = []
        valores = []
        
        campos_permitidos = [
            'numero', 'nome', 'situacao', 'localizacao', 'responsavel',
            'data_ultima_vistoria', 'data_vistoria_atual', 'auditor', 'observacoes'
        ]
        
        for campo in campos_permitidos:
            if campo in dados and dados[campo] is not None:
                campos.append(f"{campo} = ?")
                valores.append(dados[campo])
        
        if not campos:
            return False, "Nenhum campo válido para atualização"
        
        # Adicionar data de modificação
        campos.append("data_modificacao = ?")
        valores.append(datetime.now().isoformat())
        
        # Adicionar ID no final
        valores.append(bem_id)
        
        query = f"UPDATE bens SET {', '.join(campos)} WHERE id = ?"
        
        cursor.execute(query, valores)
        conn.commit()
        
        if cursor.rowcount > 0:
            return True, "Bem atualizado com sucesso"
        else:
            return False, "Bem não encontrado"
            
    except sqlite3.IntegrityError as e:
        return False, f"Erro de integridade: {str(e)}"
    except Exception as e:
        return False, f"Erro ao atualizar bem: {str(e)}"
    finally:
        if conn:
            conn.close()

def obter_bem_por_id(db_path: str, bem_id: int) -> Dict[str, Any] | None:
    """Obtém um bem pelo ID"""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT id, numero, nome, situacao, localizacao, responsavel,
                   data_ultima_vistoria, data_vistoria_atual, auditor,
                   observacoes, data_criacao, data_localizacao
            FROM bens WHERE id = ?
        ''', (bem_id,))
        
        row = cursor.fetchone()
        conn.close()
        
        if row:
            colunas = [desc[0] for desc in cursor.description]
            return dict(zip(colunas, row))
        return None
        
    except Exception as e:
        logger.error(f"Erro ao obter bem por ID {bem_id}: {str(e)}")
        return None   
    
# ==============================
# FUNÇÕES CRUD ADICIONAIS - VERSÃO SIMPLIFICADA
# ==============================

def atualizar_bem(db_path, bem_id, dados):
    """Atualiza um bem existente no banco de dados - VERSÃO SIMPLIFICADA"""
    conn = None
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Construir query dinamicamente baseada nos campos fornecidos
        campos = []
        valores = []
        
        campos_permitidos = [
            'numero', 'nome', 'situacao', 'localizacao', 'responsavel',
            'data_ultima_vistoria', 'data_vistoria_atual', 'auditor', 'observacoes'
        ]
        
        for campo in campos_permitidos:
            if campo in dados and dados[campo] is not None:
                campos.append(f"{campo} = ?")
                valores.append(dados[campo])
        
        if not campos:
            return False, "Nenhum campo válido para atualização"
        
        # Adicionar data de modificação
        campos.append("data_modificacao = ?")
        valores.append(datetime.now().isoformat())
        
        # Adicionar ID no final
        valores.append(bem_id)
        
        query = f"UPDATE bens SET {', '.join(campos)} WHERE id = ?"
        
        cursor.execute(query, valores)
        conn.commit()
        
        if cursor.rowcount > 0:
            return True, "Bem atualizado com sucesso"
        else:
            return False, "Bem não encontrado"
            
    except sqlite3.IntegrityError as e:
        return False, f"Erro de integridade: {str(e)}"
    except Exception as e:
        print(f"Erro ao atualizar bem: {str(e)}")
        return False, f"Erro ao atualizar bem: {str(e)}"
    finally:
        if conn:
            conn.close()

def obter_bem_por_id(db_path, bem_id):
    """Obtém um bem pelo ID - VERSÃO SIMPLIFICADA"""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT id, numero, nome, situacao, localizacao, responsavel,
                   data_ultima_vistoria, data_vistoria_atual, auditor,
                   observacoes, data_criacao, data_localizacao
            FROM bens WHERE id = ?
        ''', (bem_id,))
        
        row = cursor.fetchone()
        conn.close()
        
        if row:
            colunas = [desc[0] for desc in cursor.description]
            return dict(zip(colunas, row))
        return None
        
    except Exception as e:
        print(f"Erro ao obter bem por ID {bem_id}: {str(e)}")
        return None
    
def obter_bem_por_id_completo(db_path, bem_id):
    """Obtém um bem pelo ID - VERSÃO COMPLETA E ROBUSTA"""
    conn = None
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        print(f"🔍 Buscando bem com ID: {bem_id}")  # Debug
        
        # Primeiro, vamos verificar se a tabela existe
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='bens'")
        tabela_existe = cursor.fetchone()
        
        if not tabela_existe:
            print("❌ Tabela 'bens' não existe!")
            return None
        
        # Agora busca o bem
        cursor.execute('''
            SELECT id, numero, nome, situacao, localizacao, responsavel,
                   data_ultima_vistoria, data_vistoria_atual, auditor,
                   observacoes, data_criacao, data_localizacao
            FROM bens WHERE id = ?
        ''', (bem_id,))
        
        row = cursor.fetchone()
        
        if row:
            print(f"✅ Bem encontrado: ID {row[0]}, Número {row[1]}, Nome {row[2]}")
            colunas = [desc[0] for desc in cursor.description]
            bem_dict = dict(zip(colunas, row))
            print(f"📋 Dados do bem: {bem_dict}")
            return bem_dict
        else:
            print(f"❌ Nenhum bem encontrado com ID {bem_id}")
            return None
        
    except Exception as e:
        print(f"💥 ERRO ao obter bem por ID {bem_id}: {str(e)}")
        return None
    finally:
        if conn:
            conn.close()