import sqlite3
import pandas as pd
from openpyxl import load_workbook
from datetime import datetime
import os
from utils.logger import logger

def migrar_excel_para_sqlite(caminho_excel: str, caminho_sqlite: str):
    """
    Migra dados de uma planilha Excel para um banco SQLite
    """
    try:
        # Verificar se o arquivo Excel existe
        if not os.path.exists(caminho_excel):
            logger.error(f"Arquivo Excel não encontrado: {caminho_excel}")
            return False
        
        # Ler dados do Excel
        logger.info(f"Iniciando migração de {caminho_excel} para {caminho_sqlite}")
        df = pd.read_excel(caminho_excel, sheet_name='Estoque')
        
        # Conexão com SQLite
        conn = sqlite3.connect(caminho_sqlite)
        cursor = conn.cursor()
        
        # Criar tabela se não existir
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                nome TEXT,
                numero_bem TEXT UNIQUE,
                situacao TEXT DEFAULT 'Pendente',
                localizacao TEXT,
                data_criacao DATETIME DEFAULT CURRENT_TIMESTAMP,
                data_localizacao DATETIME
            )
        """)
        
        # Inserir dados
        inseridos = 0
        atualizados = 0
        
        for _, row in df.iterrows():
            # Pular linhas vazias ou de cabeçalho
            if pd.isna(row.get('Nome')) or pd.isna(row.get('Número do Bem')):
                continue
                
            # Verificar se o bem já existe
            cursor.execute("SELECT COUNT(*) FROM bens WHERE numero_bem = ?", (str(row['Número do Bem']),))
            if cursor.fetchone()[0] > 0:
                # Atualizar registro existente
                cursor.execute("""
                    UPDATE bens 
                    SET nome = ?, situacao = ?, localizacao = ?
                    WHERE numero_bem = ?
                """, (
                    str(row['Nome']), 
                    str(row.get('Situação', 'Pendente')), 
                    str(row.get('Localização', '')),
                    str(row['Número do Bem'])
                ))
                atualizados += 1
            else:
                # Inserir novo registro
                cursor.execute("""
                    INSERT INTO bens (nome, numero_bem, situacao, localizacao)
                    VALUES (?, ?, ?, ?)
                """, (
                    str(row['Nome']), 
                    str(row['Número do Bem']), 
                    str(row.get('Situação', 'Pendente')), 
                    str(row.get('Localização', ''))
                ))
                inseridos += 1
        
        conn.commit()
        conn.close()
        
        logger.info(f"Migração concluída: {inseridos} novos registros, {atualizados} atualizados")
        return True
        
    except Exception as e:
        logger.error(f"Erro durante a migração: {str(e)}")
        return False

if __name__ == "__main__":
    # Configurar caminhos (ajuste conforme necessário)
    caminho_excel = "relatorios/controle_patrimonial.xlsx"  # Substitua pelo caminho do seu Excel
    caminho_sqlite = "relatorios/controle_patrimonial.db"
    
    # Executar migração
    sucesso = migrar_excel_para_sqlite(caminho_excel, caminho_sqlite)
    
    if sucesso:
        print("Migração concluída com sucesso!")
    else:
        print("Falha na migração. Verifique os logs para detalhes.")