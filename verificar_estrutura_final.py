import sqlite3
import os

def verificar_estrutura_final():
    DB_PATH = "relatorios/controle_patrimonial.db"
    
    if not os.path.exists(DB_PATH):
        print("❌ Banco não encontrado")
        return
    
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Verificar estrutura
        cursor.execute("PRAGMA table_info(bens)")
        print("📋 ESTRUTURA DA TABELA:")
        print("ID | Nome | Tipo | Pode ser NULL | Valor Padrão | É PK")
        print("-" * 60)
        for col in cursor.fetchall():
            print(col)
        
        # Verificar dados
        print("\n📊 DADOS DE EXEMPLO:")
        cursor.execute("SELECT * FROM bens LIMIT 5")
        for row in cursor.fetchall():
            print(row)
        
        # Verificar constraints
        print("\n🔗 CONSTRAINTS:")
        cursor.execute("PRAGMA foreign_key_list(bens)")
        fks = cursor.fetchall()
        if fks:
            for fk in fks:
                print(fk)
        else:
            print("Nenhuma foreign key")
        
        conn.close()
        
    except Exception as e:
        print(f"❌ Erro: {e}")

if __name__ == "__main__":
    verificar_estrutura_final()