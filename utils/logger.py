import logging
import sys
import os

def setup_logger():
    """Configura o logger para lidar com Unicode no Windows"""
    logger = logging.getLogger('controle_patrimonial')
    logger.setLevel(logging.INFO)
    
    # Evitar múltiplos handlers
    if logger.handlers:
        return logger
    
    # Formatter sem emojis para evitar problemas de encoding
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # Handler para console
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    
    # Handler para arquivo (sem problemas de encoding)
    os.makedirs('logs', exist_ok=True)
    file_handler = logging.FileHandler(
        'logs/controle_patrimonial.log', 
        encoding='utf-8'
    )
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(formatter)
    
    # Adicionar handlers
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    
    return logger

# Criar logger
logger = setup_logger()