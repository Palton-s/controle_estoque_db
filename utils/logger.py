import logging
import os
from datetime import datetime

def setup_logger():
    """
    Configura o sistema de logs da aplicação
    Cria arquivos de log diários na pasta logs/
    """
    # Criar pasta de logs se não existir
    log_dir = "logs"
    os.makedirs(log_dir, exist_ok=True)
    
    # Configurar o logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            # Log para arquivo (diário)
            logging.FileHandler(os.path.join(log_dir, f'app_{datetime.now().strftime("%Y%m%d")}.log')),
            # Log para console
            logging.StreamHandler()
        ]
    )
    
    return logging.getLogger(__name__)

# Criar instância do logger para importação
logger = setup_logger()