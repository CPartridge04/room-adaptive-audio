import tkinter as tk
from ui import Application

if __name__ == '__main__':
    root = tk.Tk()
    app = Application(root)
    root.protocol("WM_DELETE_WINDOW", app.close)
    root.mainloop()
