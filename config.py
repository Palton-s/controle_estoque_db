# Configuração de Produção para a Aplicação Flask
import os
from pathlib import Path

class Config:
    """Configuração base"""
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-key-change-in-production'
    
    # Diretório base da aplicação
    BASE_DIR = Path(__file__).resolve().parent
    
    # Configurações de banco de dados
    DB_PATH = os.environ.get('DB_PATH') or str(BASE_DIR / 'relatorios' / 'controle_patrimonial.db')
    
    # Configurações de upload
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB max file size
    UPLOAD_FOLDER = str(BASE_DIR / 'temp')
    
    # Configurações de logs
    LOG_LEVEL = 'INFO'
    LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

class DevelopmentConfig(Config):
    """Configuração para desenvolvimento"""
    DEBUG = True
    TESTING = False
    LOG_LEVEL = 'DEBUG'

class ProductionConfig(Config):
    """Configuração para produção"""
    DEBUG = False
    TESTING = False
    SECRET_KEY = os.environ.get('SECRET_KEY')
    
    # Logs mais restritivos em produção
    LOG_LEVEL = 'WARNING'
    
    # Configurações de segurança
    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'

class TestingConfig(Config):
    """Configuração para testes"""
    DEBUG = True
    TESTING = True
    DB_PATH = ':memory:'  # SQLite em memória para testes

# Dicionário de configurações disponíveis
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': DevelopmentConfig
}