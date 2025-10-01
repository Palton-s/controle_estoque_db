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

# Configuração para rodar em subdiretório /estoque
class ReverseProxied(object):
    def __init__(self, app, script_name=None, scheme=None, server=None):
        self.app = app
        self.script_name = script_name
        self.scheme = scheme
        self.server = server

    def __call__(self, environ, start_response):
        script_name = environ.get('HTTP_X_SCRIPT_NAME', '') or self.script_name
        if script_name:
            environ['SCRIPT_NAME'] = script_name
            path_info = environ['PATH_INFO']
            if path_info.startswith(script_name):
                environ['PATH_INFO'] = path_info[len(script_name):]
        scheme = environ.get('HTTP_X_SCHEME', '') or self.scheme
        if scheme:
            environ['wsgi.url_scheme'] = scheme
        server = environ.get('HTTP_X_FORWARDED_SERVER', '') or self.server
        if server:
            environ['HTTP_HOST'] = server
        return self.app(environ, start_response)

# Aplicar middleware para subdiretório
application = ReverseProxied(application, script_name='/estoque')

if __name__ == "__main__":
    application.run()