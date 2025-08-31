import sqlite3
import os
from utils.logger import logger

def debug_buscar_detalhes(numero_bem):
    """Debug da função de buscar detalhes"""
    DB_PATH = "relatorios/controle_patrimonial.db"
    
    if not os.path.exists(DB_PATH):
        print("❌ Banco não encontrado")
        return
    
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        print(f"🔍 Buscando bem: {numero_bem}")
        
        # Primeiro verificar se o bem existe
        cursor.execute("SELECT COUNT(*) FROM bens WHERE numero = ?", (numero_bem,))
        count = cursor.fetchone()[0]
        print(f"✅ Bem encontrado: {count > 0}")
        
        if count > 0:
            # Buscar todos os dados do bem
            cursor.execute("SELECT * FROM bens WHERE numero = ?", (numero_bem,))
            resultado = cursor.fetchone()
            
            print("📋 Dados completos do bem:")
            for key in resultado.keys():
                print(f"  {key}: {resultado[key]}")
            
            # Testar a formatação que estamos usando
            detalhes = {
                'nome': resultado['nome'],
                'numero': resultado['numero'],
                'situacao': resultado['situacao'],
                'localizacao': resultado['localizacao'] or 'Não informada'
            }
            
            print("\n🎯 Detalhes formatados:")
            for key, value in detalhes.items():
                print(f"  {key}: {value}")
        
        conn.close()
        
    except Exception as e:
        print(f"❌ Erro: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    # Testar com um número que você sabe que existe
    debug_buscar_detalhes("367248")  # Use um número que existe no seu banco