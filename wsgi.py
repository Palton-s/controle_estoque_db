#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WSGI Configuration for Controle de Estoque
Este arquivo é usado pelo Apache mod_wsgi para servir a aplicação Flask
"""

import sys
import os

# Adicionar o diretório da aplicação ao Python path
sys.path.insert(0, '/var/www/controle_estoque_db/')

# Definir variáveis de ambiente necessárias
os.environ['FLASK_APP'] = 'app.py'
os.environ['FLASK_ENV'] = 'production'

# Importar a aplicação Flask
from app import app as application

# Configurações específicas para produção
application.config['DEBUG'] = False
application.config['TESTING'] = False

if __name__ == "__main__":
    application.run()