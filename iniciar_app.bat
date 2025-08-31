@echo off
setlocal

REM Caminho completo para o executável
set "APP_PATH=D:\controle_estoque_web\dist\main.exe"

REM Caminho para salvar o log
set "LOG_PATH=D:\controle_estoque_web\logs\app_log.txt"

REM Cria a pasta de logs se não existir
if not exist "D:\controle_estoque_web\logs" (
    mkdir "D:\controle_estoque_web\logs"
)

REM Inicia o aplicativo e salva o log
start "" "%APP_PATH%" > "%LOG_PATH%" 2>&1

REM Aguarda 2 segundos para o servidor iniciar
timeout /t 2 >nul

REM Abre o navegador na URL do Flask
start "" "http://127.0.0.1:5000"

endlocal
