import tkinter as tk
from tkinter import ttk

root = tk.Tk()
root.title("Control display test")
root.geometry("500x300")

tk.Label(root, text="Standard Tk label", bg="yellow", fg="black").pack(pady=20)
ttk.Label(root, text="Themed ttk label").pack(pady=20)
ttk.Button(root, text="Themed ttk button").pack(pady=20)

root.mainloop()