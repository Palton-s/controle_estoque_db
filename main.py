from app import app
import webbrowser
import threading

def abrir_navegador():
    webbrowser.open("http://127.0.0.1:5000")

if __name__ == '__main__':
    threading.Timer(1.5, abrir_navegador).start()
    app.run()
