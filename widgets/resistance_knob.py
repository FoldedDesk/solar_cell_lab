"""
Resistance box widgets with adaptive sizing.
"""

import tkinter as tk


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


class DigitSelector(tk.Frame):
    """One selector column with decrement/value/increment controls."""

    def __init__(self, parent, label="x100", on_change=None, ui_scale=1.0, **kwargs):
        super().__init__(parent, bg="#2b2b2b", **kwargs)
        self.value = 0
        self.on_change = on_change
        self.ui_scale = _clamp(float(ui_scale), 1.0, 2.0)

        small_font = ("Consolas", max(12, int(12 * self.ui_scale)))
        digit_font = ("Consolas", max(18, int(18 * self.ui_scale)), "bold")
        btn_width = max(3, int(3 * self.ui_scale))
        pad_y = max(2, int(2 * self.ui_scale))

        tk.Label(self, text=label, bg="#2b2b2b", fg="#aaa", font=small_font).pack()
        tk.Button(
            self,
            text="-",
            width=btn_width,
            bg="#444",
            fg="#fff",
            activebackground="#666",
            relief=tk.FLAT,
            font=small_font,
            command=self._dec,
        ).pack(pady=pad_y)
        self.digit_label = tk.Label(
            self,
            text="0",
            bg="#1a1a1a",
            fg="#ff6b35",
            width=btn_width,
            font=digit_font,
        )
        self.digit_label.pack(pady=pad_y)
        tk.Button(
            self,
            text="+",
            width=btn_width,
            bg="#444",
            fg="#fff",
            activebackground="#666",
            relief=tk.FLAT,
            font=small_font,
            command=self._inc,
        ).pack(pady=pad_y)

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
    """Five-digit resistance box: x10000, x1000, x100, x10, x1."""

    def __init__(self, parent, on_change=None, ui_scale=1.0, **kwargs):
        super().__init__(parent, bg="#1e1e1e", **kwargs)
        self.on_change = on_change
        self.ui_scale = _clamp(float(ui_scale), 1.0, 2.0)

        title_font = ("Microsoft YaHei", max(13, int(13 * self.ui_scale)), "bold")
        value_font = ("Consolas", max(16, int(16 * self.ui_scale)), "bold")
        padx = max(3, int(3 * self.ui_scale))
        pady_top = max(6, int(6 * self.ui_scale))
        pady_mid = max(3, int(3 * self.ui_scale))

        tk.Label(self, text="电阻箱 (Ω)", bg="#1e1e1e", fg="#ff6b35", font=title_font).pack(pady=(pady_top, pady_mid))

        knobs_frame = tk.Frame(self, bg="#1e1e1e")
        knobs_frame.pack(padx=padx)

        multipliers = [10000, 1000, 100, 10, 1]
        labels = ["x10k", "x1k", "x100", "x10", "x1"]

        self.selectors = []
        for mult, lbl in zip(multipliers, labels):
            sel = DigitSelector(knobs_frame, label=lbl, on_change=self._on_change, ui_scale=self.ui_scale)
            sel.pack(side=tk.LEFT, padx=padx)
            self.selectors.append((mult, sel))

        self.total_label = tk.Label(self, text="R = 0 Ω", bg="#1e1e1e", fg="#00ff88", font=value_font)
        self.total_label.pack(pady=(max(8, int(8 * self.ui_scale)), max(6, int(6 * self.ui_scale))))

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
