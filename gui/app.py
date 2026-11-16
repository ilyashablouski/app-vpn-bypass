#!/usr/bin/env python3
"""VPN Bypass: GUI для управления исключениями из Urban VPN (macOS)."""
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

import core

POLL_MS = 2000


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("VPN Bypass")
        self.geometry("520x560")
        self.minsize(460, 480)
        self.entries = core.load_entries()
        self._build()
        self._refresh_list()
        self._poll()

    def _build(self):
        pad = {"padx": 12, "pady": 6}
        status = ttk.LabelFrame(self, text="Состояние")
        status.pack(fill="x", **pad)
        self.vpn_label = ttk.Label(status, font=("TkDefaultFont", 13, "bold"))
        self.vpn_label.pack(anchor="w", padx=10, pady=(8, 2))
        self.app_label = ttk.Label(status)
        self.app_label.pack(anchor="w", padx=10)
        self.script_label = ttk.Label(status)
        self.script_label.pack(anchor="w", padx=10, pady=(2, 4))
        self.toggle_btn = ttk.Button(status, command=self._toggle)
        self.toggle_btn.pack(fill="x", padx=10, pady=(4, 10))

        lst = ttk.LabelFrame(self, text="Исключения (VPN для них не используется)")
        lst.pack(fill="both", expand=True, **pad)
        self.tree = ttk.Treeview(lst, columns=("kind", "value"), show="headings",
                                 selectmode="extended", height=8)
        self.tree.heading("kind", text="Тип")
        self.tree.heading("value", text="Значение")
        self.tree.column("kind", width=90, stretch=False)
        self.tree.pack(fill="both", expand=True, padx=10, pady=(8, 4))
        self.tree.bind("<BackSpace>", lambda e: self._remove())
        self.tree.bind("<Delete>", lambda e: self._remove())

        row = ttk.Frame(lst)
        row.pack(fill="x", padx=10, pady=(0, 4))
        self.host_var = tk.StringVar()
        entry = ttk.Entry(row, textvariable=self.host_var)
        entry.pack(side="left", fill="x", expand=True)
        entry.bind("<Return>", lambda e: self._add_host())
        ttk.Button(row, text="Добавить домен/IP", command=self._add_host).pack(side="left", padx=(6, 0))

        row2 = ttk.Frame(lst)
        row2.pack(fill="x", padx=10, pady=(0, 10))
        ttk.Button(row2, text="Добавить приложение…", command=self._add_app).pack(side="left")
        ttk.Button(row2, text="Удалить выбранное", command=self._remove).pack(side="right")

        self.hint = ttk.Label(self, foreground="gray", wraplength=480,
                              text="Изменения подхватываются запущенным скриптом автоматически "
                                   "(раз в 30 секунд). Для запуска и остановки потребуется пароль администратора.")
        self.hint.pack(fill="x", padx=12, pady=(0, 10))

    def _refresh_list(self):
        self.tree.delete(*self.tree.get_children())
        for kind, value in self.entries:
            self.tree.insert("", "end", values=("Приложение" if kind == "app" else "Домен/IP", value))

    def _save(self):
        core.save_entries(self.entries)
        self._refresh_list()

    def _add_host(self):
        value = core.normalize_host(self.host_var.get())
        if not core.valid_host(value):
            messagebox.showerror("Некорректное значение", "Введите домен (example.com), IP или подсеть (10.0.0.0/8).")
            return
        if core.add_entry(self.entries, "host", value):
            self._save()
        self.host_var.set("")

    def _add_app(self):
        path = self._ask_app()
        if not path:
            return
        if core.add_entry(self.entries, "app", core.app_process_name(path)):
            self._save()

    def _ask_app(self):
        return filedialog.askdirectory(title="Выберите приложение (.app)", initialdir="/Applications")

    def _remove(self):
        values = {self.tree.item(i, "values")[1] for i in self.tree.selection()}
        if not values:
            return
        self.entries = [e for e in self.entries if e[1] not in values]
        self._save()

    def _toggle(self):
        if core.running_pid():
            ok, err = core.stop_script()
        else:
            if not core.is_vpn_connected():
                messagebox.showwarning("VPN выключен", "Сначала включите Urban VPN.")
                return
            ok, err = core.start_script()
        if not ok and "User canceled" not in err:
            messagebox.showerror("Ошибка", err or "Не удалось выполнить команду")
        self._update_status()

    def _update_status(self):
        vpn = core.is_vpn_connected()
        running = core.running_pid() is not None
        self.vpn_label.config(text="Urban VPN: включён" if vpn else "Urban VPN: выключен",
                              foreground="#1a7f37" if vpn else "#cf222e")
        self.app_label.config(text="Приложение Urban VPN запущено" if core.is_vpn_app_running()
                              else "Приложение Urban VPN не запущено")
        self.script_label.config(text="Исключения: работают" if running else "Исключения: остановлены")
        self.toggle_btn.config(text="Остановить исключения" if running else "Запустить исключения")
        self.toggle_btn.state(["!disabled"] if (vpn or running) else ["disabled"])

    def _poll(self):
        self._update_status()
        self.after(POLL_MS, self._poll)


if __name__ == "__main__":
    App().mainloop()
