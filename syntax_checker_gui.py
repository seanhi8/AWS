import os
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext

SUPPORTED_EXTS = {'.py', '.ts', '.js'}

def find_supported_files(path):
    files = []
    if os.path.isfile(path) and os.path.splitext(path)[1] in SUPPORTED_EXTS:
        files.append(path)
    elif os.path.isdir(path):
        for root, _, filenames in os.walk(path):
            for name in filenames:
                ext = os.path.splitext(name)[1]
                if ext in SUPPORTED_EXTS:
                    files.append(os.path.join(root, name))
    return files

def check_python(file_path):
    try:
        subprocess.check_output(['python', '-m', 'py_compile', file_path], stderr=subprocess.STDOUT)
        return None
    except subprocess.CalledProcessError as e:
        return e.output.decode()

def check_typescript(file_path):
    try:
        subprocess.check_output(['tsc', '--noEmit', file_path], stderr=subprocess.STDOUT)
        return None
    except subprocess.CalledProcessError as e:
        return e.output.decode()

def check_javascript(file_path):
    try:
        subprocess.check_output(['node', '--check', file_path], stderr=subprocess.STDOUT)
        return None
    except subprocess.CalledProcessError as e:
        return e.output.decode()

def check_file(file_path):
    ext = os.path.splitext(file_path)[1]
    if ext == '.py':
        return check_python(file_path)
    elif ext == '.ts':
        return check_typescript(file_path)
    elif ext == '.js':
        return check_javascript(file_path)
    return None

def analyze(path, output_box):
    output_box.delete(1.0, tk.END)
    files = find_supported_files(path)
    if not files:
        output_box.insert(tk.END, "未找到支持的文件（.py, .ts, .js）\n")
        return

    for file in files:
        output_box.insert(tk.END, f"\n检查文件: {file}\n")
        result = check_file(file)
        if result:
            output_box.insert(tk.END, f"发现错误：\n{result}\n")
        else:
            output_box.insert(tk.END, "语法无误\n")

def browse_file(output_box):
    file_path = filedialog.askopenfilename(filetypes=[("Code files", "*.py *.ts *.js")])
    if file_path:
        analyze(file_path, output_box)

def browse_folder(output_box):
    folder_path = filedialog.askdirectory()
    if folder_path:
        analyze(folder_path, output_box)

def create_gui():
    root = tk.Tk()
    root.title("多语言语法检查工具")
    root.geometry("700x500")

    frame = tk.Frame(root)
    frame.pack(pady=10)

    btn_file = tk.Button(frame, text="选择文件", command=lambda: browse_file(output_box), width=15)
    btn_file.pack(side=tk.LEFT, padx=10)

    btn_folder = tk.Button(frame, text="选择文件夹", command=lambda: browse_folder(output_box), width=15)
    btn_folder.pack(side=tk.LEFT, padx=10)

    output_box = scrolledtext.ScrolledText(root, wrap=tk.WORD, font=("Courier", 10))
    output_box.pack(expand=True, fill='both', padx=10, pady=10)

    root.mainloop()

if __name__ == '__main__':
    create_gui()

