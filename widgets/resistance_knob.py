"""
电阻箱组件 — 五档紧凑按钮式（▲/▼），替代旋钮
"""

import tkinter as tk


class DigitSelector(tk.Frame):
    """单个档位：紧凑的 ▲ [数字] ▼ 纵向排列"""

    def __init__(self, parent, label="×100", on_change=None, **kwargs):
        super().__init__(parent, bg="#2b2b2b", **kwargs)
        self.value = 0
        self.on_change = on_change

        # 标签
        tk.Label(self, text=label, bg="#2b2b2b", fg="#aaa",
                 font=("Consolas", 8)).pack()

        # ▲ 按钮
        tk.Button(self, text="▲", width=2, bg="#444", fg="#fff",
                  activebackground="#666", relief=tk.FLAT,
                  font=("Consolas", 8),
                  command=self._dec).pack(pady=1)

        # 数字
        self.digit_label = tk.Label(self, text="0", bg="#1a1a1a",
                                    fg="#ff6b35", width=2,
                                    font=("Consolas", 14, "bold"))
        self.digit_label.pack(pady=1)

        # ▼ 按钮
        tk.Button(self, text="▼", width=2, bg="#444", fg="#fff",
                  activebackground="#666", relief=tk.FLAT,
                  font=("Consolas", 8),
                  command=self._inc).pack(pady=1)

    def _inc(self):
        self.value = (self.value + 1) % 10
        self._update()

    def _dec(self):
        self.value = (self.value - 1) % 10
        self._update()

    def _update(self):
        self.digit_label.config(text=str(self.value))
        if self.on_change:
            self.on_change()

    def get_value(self):
        return self.value

    def set_value(self, v):
        self.value = int(v) % 10
        self.digit_label.config(text=str(self.value))


class ResistanceBox(tk.Frame):
    """五档电阻箱：×10000, ×1000, ×100, ×10, ×1"""

    def __init__(self, parent, on_change=None, **kwargs):
        super().__init__(parent, bg="#1e1e1e", **kwargs)
        self.on_change = on_change

        tk.Label(self, text="电阻箱 (Ω)", bg="#1e1e1e", fg="#ff6b35",
                 font=("Microsoft YaHei", 10, "bold")).pack(pady=(5, 2))

        knobs_frame = tk.Frame(self, bg="#1e1e1e")
        knobs_frame.pack(padx=2)

        multipliers = [10000, 1000, 100, 10, 1]
        labels = ["×10k", "×1k", "×100", "×10", "×1"]

        self.selectors = []
        for mult, lbl in zip(multipliers, labels):
            sel = DigitSelector(knobs_frame, label=lbl,
                                on_change=self._on_change)
            sel.pack(side=tk.LEFT, padx=1)
            self.selectors.append((mult, sel))

        self.total_label = tk.Label(self, text="R = 0 Ω", bg="#1e1e1e",
                                    fg="#00ff88",
                                    font=("Consolas", 12, "bold"))
        self.total_label.pack(pady=(6, 5))

    def _on_change(self):
        total = self.get_resistance()
        self.total_label.config(text=f"R = {total:,} Ω")
        if self.on_change:
            self.on_change(total)

    def get_resistance(self):
        return sum(m * s.get_value() for m, s in self.selectors)

    def set_resistance(self, total):
        total = int(total)
        for mult, sel in self.selectors:
            sel.set_value(total // mult)
            total %= mult
        self._on_change()
