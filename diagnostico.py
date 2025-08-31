import os
import sqlite3
from utils.logger import logger

# Verificar se o banco existe
DB_PATH = "relatorios/controle_patrimonial.db"
print(f"Caminho do banco: {DB_PATH}")
print(f"Banco existe: {os.path.exists(DB_PATH)}")

if os.path.exists(DB_PATH):
    try:
        # Conectar e verificar tabelas
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Verificar tabelas no banco
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        print(f"Tabelas no banco: {tables}")
        
        # Verificar se a tabela 'bens' existe
        if any('bens' in table for table in tables):
            cursor.execute("SELECT COUNT(*) FROM bens")
            count = cursor.fetchone()[0]
            print(f"Total de registros na tabela 'bens': {count}")
            
            # Mostrar alguns registros
            cursor.execute("SELECT nome, numero_bem, situacao FROM bens LIMIT 5")
            sample_data = cursor.fetchall()
            print("Amostra de dados:")
            for row in sample_data:
                print(row)
        else:
            print("Tabela 'bens' não encontrada!")
            
        conn.close()
        
    except Exception as e:
        print(f"Erro ao acessar banco: {e}")
else:
    print("Banco de dados não encontrado. Execute a migração primeiro.")