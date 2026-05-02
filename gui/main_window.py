"""
主窗口 — 虚拟实验台
实验一：固定光源+距离(30cm)，改变电阻 → 用户手动填 U, I
实验二：固定光源+电阻，改变距离 → 记录 d, U, I, P
实验三：固定距离+电阻，改变光强 → 记录 E, U, I, P
"""

import tkinter as tk
from tkinter import ttk
import numpy as np
import matplotlib
matplotlib.use("TkAgg")
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import matplotlib.font_manager as fm

plt_font = fm.FontProperties(family="Microsoft YaHei")

import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from physics import (solve_iv_curve, solve_voc, solve_isc, find_mpp,
                     calc_fill_factor, DEFAULT_PARAMS, calc_light_intensity,
                     get_experimental_data)

# ── 颜色主题 ──
BG = "#1a1a2e"
PANEL_BG = "#16213e"
FG = "#e0e0e0"
ACCENT = "#ff6b35"
ACCENT2 = "#00ff88"
GRID_COLOR = "#333"


def solve_operating_point(params, R_ohm):
    """给定负载电阻 R，求工作点 (V, I, P)。"""
    if R_ohm <= 0:
        return 0.0, 0.0, 0.0
    V_arr, I_arr, _ = solve_iv_curve(params)
    I_load = V_arr / R_ohm
    diff = I_arr - I_load
    for i in range(len(diff) - 1):
        if diff[i] * diff[i + 1] <= 0:
            t = diff[i] / (diff[i] - diff[i + 1])
            V_op = V_arr[i] + t * (V_arr[i + 1] - V_arr[i])
            I_op = I_arr[i] + t * (I_arr[i + 1] - I_arr[i])
            return float(V_op), float(I_op), float(V_op * I_op)
    idx = np.argmin(np.abs(diff))
    return float(V_arr[idx]), float(I_arr[idx]), float(V_arr[idx] * I_arr[idx])


# ═══════════════════════════════════════════════
#  手动输入对话框
# ═══════════════════════════════════════════════

class _ManualInputDialog:
    """弹窗让用户手动输入 U (V) 和 I (mA)。
    Enter 在 U 框 → 跳到 I 框；Enter 在 I 框 → 确认提交。
    """

    def __init__(self, parent, R):
        self.result = None
        self.top = tk.Toplevel(parent)
        self.top.title("手动输入测量数据")
        self.top.configure(bg=BG)
        self.top.geometry("360x240")
        self.top.resizable(False, False)
        self.top.grab_set()

        tk.Label(self.top, text="记录数据点", bg=ACCENT, fg="#fff",
                 font=("Microsoft YaHei", 13, "bold")).pack(fill=tk.X, ipady=6)

        tk.Label(self.top, text="当前电阻 R = {:g} Ω".format(R),
                 bg=BG, fg="#aaa", font=("Microsoft YaHei", 10)).pack(pady=(10, 12))

        # U 输入
        f1 = tk.Frame(self.top, bg=BG)
        f1.pack(fill=tk.X, padx=30, pady=4)
        tk.Label(f1, text="电压 U (V):", bg=BG, fg=FG,
                 font=("Microsoft YaHei", 11), width=12, anchor="e").pack(side=tk.LEFT)
        self.u_var = tk.StringVar(value="")
        self.u_entry = tk.Entry(f1, textvariable=self.u_var, font=("Consolas", 13),
                                bg="#1a1a1a", fg="#00ff88", insertbackground="#00ff88",
                                width=12, relief=tk.SUNKEN, bd=2)
        self.u_entry.pack(side=tk.LEFT, padx=8)
        self.u_entry.focus_set()

        # I 输入
        f2 = tk.Frame(self.top, bg=BG)
        f2.pack(fill=tk.X, padx=30, pady=4)
        tk.Label(f2, text="电流 I (mA):", bg=BG, fg=FG,
                 font=("Microsoft YaHei", 11), width=12, anchor="e").pack(side=tk.LEFT)
        self.i_var = tk.StringVar(value="")
        self.i_entry = tk.Entry(f2, textvariable=self.i_var, font=("Consolas", 13),
                                bg="#1a1a1a", fg="#00ff88", insertbackground="#00ff88",
                                width=12, relief=tk.SUNKEN, bd=2)
        self.i_entry.pack(side=tk.LEFT, padx=8)

        # Enter 键绑定
        self.u_entry.bind("<Return>", lambda e: self.i_entry.focus_set())
        self.i_entry.bind("<Return>", lambda e: self._ok())

        # 按钮
        bf = tk.Frame(self.top, bg=BG)
        bf.pack(fill=tk.X, padx=30, pady=(12, 0))
        tk.Button(bf, text="确认", bg="#2a6", fg="#fff",
                  font=("Microsoft YaHei", 11, "bold"), relief=tk.FLAT,
                  activebackground="#3b7", width=10,
                  command=self._ok).pack(side=tk.LEFT, expand=True, padx=4)
        tk.Button(bf, text="取消", bg="#644", fg="#fff",
                  font=("Microsoft YaHei", 11), relief=tk.FLAT,
                  activebackground="#855", width=10,
                  command=self._cancel).pack(side=tk.LEFT, expand=True, padx=4)

        self.top.bind("<Escape>", lambda e: self._cancel())

    def _ok(self):
        try:
            u = float(self.u_var.get().strip())
            i = float(self.i_var.get().strip())
        except ValueError:
            self._flash_error("请输入有效数字！")
            return
        if u < 0 or i < 0:
            self._flash_error("数值不能为负！")
            return
        self.result = (u, i)
        self.top.destroy()

    def _cancel(self):
        self.result = None
        self.top.destroy()

    def _flash_error(self, msg):
        for w in self.top.winfo_children():
            if isinstance(w, tk.Label) and w.cget("bg") == "#ff4444":
                w.destroy()
        tk.Label(self.top, text=msg, bg="#ff4444", fg="#fff",
                 font=("Microsoft YaHei", 10, "bold")).pack(fill=tk.X)


# ═══════════════════════════════════════════════
#  实验一：改变电阻（手动填数据）
# ═══════════════════════════════════════════════

class ExperimentOneTab:
    """实验一：固定光源+距离，改变电阻，用户手动输入 U、I。"""

    def __init__(self, parent_frame):
        self.frame = parent_frame
        self.title = "改变负载电阻"
        self.params = {k: v for k, v in DEFAULT_PARAMS["single"].items()}
        self.data_points = []
        self.distance_cm = 30.0
        self.light_intensity = 1000.0
        self._build()

    def _build(self):
        left = tk.Frame(self.frame, bg=PANEL_BG, width=280)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 6))
        left.pack_propagate(False)
        right = tk.Frame(self.frame, bg=BG)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self._build_control(left)
        self._build_right(right)

    # ── 左侧控制面板 ──

    def _build_control(self, parent):
        # 电池类型（仅单晶硅，无选择）
        tk.Label(parent, text="电池类型", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 10, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        tf = tk.Frame(parent, bg=PANEL_BG)
        tf.pack(fill=tk.X, padx=10)
        self.cell_type_var = tk.StringVar(value="single")
        tk.Label(tf, text="单晶硅", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(side=tk.LEFT, padx=5)
        ttk.Separator(parent, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        # 电阻箱（含 ×0.1）+ 手动输入框
        self._build_resistance_box(parent)

        ttk.Separator(parent, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        # 固定条件
        info = tk.Frame(parent, bg=PANEL_BG)
        info.pack(fill=tk.X, padx=10, pady=4)
        tk.Label(info, text="固定条件:", bg=PANEL_BG, fg="#888",
                 font=("Microsoft YaHei", 9)).pack(anchor="w")
        tk.Label(info, text="  光源功率: 100 W", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(anchor="w")
        tk.Label(info, text="  光源-板距离: 30 cm", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(anchor="w")

        ttk.Separator(parent, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        # 操作按钮
        tk.Button(parent, text="● 记录数据（手动输入）",
                  bg=ACCENT, fg="#fff", font=("Microsoft YaHei", 11, "bold"),
                  activebackground="#ff8855", relief=tk.FLAT,
                  command=self._record_point).pack(fill=tk.X, padx=10, pady=4, ipady=4)

        btn_frame = tk.Frame(parent, bg=PANEL_BG)
        btn_frame.pack(fill=tk.X, padx=10, pady=4)
        tk.Button(btn_frame, text="绘图（≥10组）", bg="#2a6", fg="#fff",
                  font=("Microsoft YaHei", 10), relief=tk.FLAT,
                  activebackground="#3b7",
                  command=self._draw_plot).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        tk.Button(btn_frame, text="清除数据", bg="#644", fg="#fff",
                  font=("Microsoft YaHei", 10), relief=tk.FLAT,
                  activebackground="#855",
                  command=self._clear_data).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        tk.Button(parent, text="导入实验一实测标准数据", bg="#885500", fg="#fff",
                  font=("Microsoft YaHei", 10, "bold"), relief=tk.FLAT,
                  activebackground="#aa7722",
                  command=self._load_standard_data).pack(fill=tk.X, padx=10, pady=2, ipady=3)

        tk.Button(parent, text="数据分析", bg="#2266cc", fg="#fff",
                  font=("Microsoft YaHei", 11, "bold"),
                  activebackground="#3377dd", relief=tk.FLAT,
                  command=self._show_analysis).pack(fill=tk.X, padx=10, pady=6, ipady=4)

    def _build_resistance_box(self, parent):
        tk.Label(parent, text="━━━ 负载电阻 ━━━", bg=PANEL_BG, fg=ACCENT,
                 font=("Microsoft YaHei", 10, "bold")).pack(anchor="w", padx=10, pady=(0, 2))
        box = tk.Frame(parent, bg="#1e1e1e", relief=tk.RAISED, bd=1)
        box.pack(fill=tk.X, padx=10, pady=4)

        tk.Label(box, text="电阻箱 (Ω)", bg="#1e1e1e", fg="#ff6b35",
                 font=("Microsoft YaHei", 9, "bold")).pack(pady=(4, 2))

        # 旋钮区
        knobs = tk.Frame(box, bg="#1e1e1e")
        knobs.pack(padx=2)
        self.r_digits = []
        self.r_multipliers = [10000, 1000, 100, 10, 1, 0.1]
        labels = ["×10k", "×1k", "×100", "×10", "×1", "×0.1"]
        for i, lbl in enumerate(labels):
            col = tk.Frame(knobs, bg="#2b2b2b")
            col.pack(side=tk.LEFT, padx=1)
            tk.Label(col, text=lbl, bg="#2b2b2b", fg="#aaa",
                     font=("Consolas", 7)).pack()
            tk.Button(col, text="▲", width=2, bg="#444", fg="#fff",
                      font=("Consolas", 8), relief=tk.FLAT,
                      command=lambda idx=i: self._r_digit_inc(idx)).pack(pady=1)
            digit_lbl = tk.Label(col, text="0", bg="#1a1a1a", fg="#ff6b35",
                                 width=2, font=("Consolas", 13, "bold"))
            digit_lbl.pack(pady=1)
            tk.Button(col, text="▼", width=2, bg="#444", fg="#fff",
                      font=("Consolas", 8), relief=tk.FLAT,
                      command=lambda idx=i: self._r_digit_dec(idx)).pack(pady=1)
            self.r_digits.append(digit_lbl)

        # 总电阻显示
        self.r_total_label = tk.Label(box, text="R = 0.0 Ω", bg="#1e1e1e",
                                      fg="#00ff88", font=("Consolas", 12, "bold"))
        self.r_total_label.pack(pady=(4, 4))
        self.r_value = 0.0

        # 手动输入电阻值
        manual_f = tk.Frame(box, bg="#1e1e1e")
        manual_f.pack(fill=tk.X, padx=8, pady=(0, 6))
        tk.Label(manual_f, text="直接输入:", bg="#1e1e1e", fg="#aaa",
                 font=("Microsoft YaHei", 8)).pack(side=tk.LEFT)
        self.r_manual_var = tk.StringVar(value="")
        r_manual_entry = tk.Entry(manual_f, textvariable=self.r_manual_var,
                                  font=("Consolas", 11), bg="#1a1a1a", fg="#00ff88",
                                  insertbackground="#00ff88", width=8,
                                  relief=tk.SUNKEN, bd=1)
        r_manual_entry.pack(side=tk.LEFT, padx=4)
        r_manual_entry.bind("<Return>", self._on_r_manual_enter)
        tk.Label(manual_f, text="Ω", bg="#1e1e1e", fg="#aaa",
                 font=("Consolas", 9)).pack(side=tk.LEFT)
        tk.Button(manual_f, text="设定", bg="#335", fg="#fff",
                  font=("Microsoft YaHei", 8), relief=tk.FLAT, padx=6,
                  activebackground="#446",
                  command=lambda: self._on_r_manual_enter(None)).pack(side=tk.LEFT, padx=2)

    # ── 电阻箱旋钮操作 ──

    def _r_digit_inc(self, idx):
        lbl = self.r_digits[idx]
        v = (int(lbl.cget("text")) + 1) % 10
        lbl.config(text=str(v))
        self._r_update_total()

    def _r_digit_dec(self, idx):
        lbl = self.r_digits[idx]
        v = (int(lbl.cget("text")) - 1) % 10
        lbl.config(text=str(v))
        self._r_update_total()

    def _r_update_total(self):
        total = 0.0
        for i, mult in enumerate(self.r_multipliers):
            total += int(self.r_digits[i].cget("text")) * mult
        total = round(total, 1)
        self.r_value = total
        if total == int(total):
            self.r_total_label.config(text="R = {} Ω".format(int(total)))
        else:
            self.r_total_label.config(text="R = {:.1f} Ω".format(total))
        self.r_manual_var.set("")

    def _on_r_manual_enter(self, event):
        """手动输入电阻值"""
        try:
            val = float(self.r_manual_var.get().strip())
            if val < 0:
                raise ValueError
        except ValueError:
            self._show_toast("请输入有效的电阻值（≥0）")
            return
        self.r_value = val
        if val == int(val):
            self.r_total_label.config(text="R = {} Ω".format(int(val)))
        else:
            self.r_total_label.config(text="R = {:.1f} Ω".format(val))
        # 同步电阻箱位数显示（按位拆分，避免出现 99 Ω 显示成 109 Ω 的问题）
        remaining = val
        for i, mult in enumerate(self.r_multipliers):
            if mult >= 1:
                digit = int(remaining // mult)
                remaining -= digit * mult
            else:
                digit = int(round(remaining / mult))
            digit = max(0, min(9, digit))
            self.r_digits[i].config(text=str(digit))

    # ── 电池类型切换 ──

    def _on_type_change(self):
        t = self.cell_type_var.get()
        self.params = {k: v for k, v in DEFAULT_PARAMS[t].items()}

    # ── 右侧：两张图 + 数据表 ──

    def _build_right(self, parent):
        chart_frame = tk.Frame(parent, bg=BG)
        chart_frame.pack(fill=tk.BOTH, expand=True)

        # 图1：伏安特性曲线 (I vs U)
        self.fig1 = Figure(figsize=(4, 3.2), dpi=100, facecolor=BG)
        self.ax1 = self.fig1.add_subplot(111)
        self._style_ax(self.ax1, title="伏安特性曲线", xlabel="U (V)", ylabel="I (mA)")
        self.canvas1 = FigureCanvasTkAgg(self.fig1, master=chart_frame)
        self.canvas1.get_tk_widget().pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 2))

        # 图2：功率输出曲线 (P vs R)
        self.fig2 = Figure(figsize=(4, 3.2), dpi=100, facecolor=BG)
        self.ax2 = self.fig2.add_subplot(111)
        self._style_ax(self.ax2, title="功率输出曲线", xlabel="R (Ω)", ylabel="P (mW)")
        self.canvas2 = FigureCanvasTkAgg(self.fig2, master=chart_frame)
        self.canvas2.get_tk_widget().pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(2, 0))

        # 数据表
        table_frame = tk.Frame(parent, bg=PANEL_BG, height=180)
        table_frame.pack(fill=tk.X, padx=0, pady=(4, 0))
        table_frame.pack_propagate(False)

        hdr = tk.Frame(table_frame, bg=PANEL_BG)
        hdr.pack(fill=tk.X, padx=8, pady=(4, 2))
        tk.Label(hdr, text="实验数据记录（手动输入）", bg=PANEL_BG, fg=ACCENT,
                 font=("Microsoft YaHei", 10, "bold")).pack(side=tk.LEFT)
        tk.Button(hdr, text="删除选中行", bg="#644", fg="#fff",
                  font=("Microsoft YaHei", 9), relief=tk.FLAT,
                  activebackground="#855",
                  command=self._delete_selected).pack(side=tk.RIGHT, padx=4)

        cols = ("序号", "R (Ω)", "U (V)", "I (mA)", "P (mW)")
        self.tree = ttk.Treeview(table_frame, columns=cols, show="headings", height=6)
        for c in cols:
            self.tree.heading(c, text=c)
            w = 50 if c == "序号" else 90
            self.tree.column(c, width=w, anchor="center")
        vsb = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(8, 0))
        vsb.pack(side=tk.RIGHT, fill=tk.Y, padx=(0, 8))

    def _style_ax(self, ax, title="", xlabel="", ylabel=""):
        ax.set_facecolor("#0f0f23")
        ax.set_title(title, fontproperties=plt_font, color=FG, fontsize=11, pad=6)
        ax.set_xlabel(xlabel, fontproperties=plt_font, color=FG, fontsize=9)
        ax.set_ylabel(ylabel, fontproperties=plt_font, color=FG, fontsize=9)
        ax.tick_params(colors="#888", labelsize=8)
        for spine in ax.spines.values():
            spine.set_color(GRID_COLOR)
        ax.grid(True, alpha=0.2, color=GRID_COLOR)

    def _best_point_index(self):
        """最佳点规则：P 最大；若 P 在容差内相同，取 R 更小者。"""
        if not self.data_points:
            return None
        eps = 1e-9
        best_i = 0
        best_p = self.data_points[0]["P"]
        best_r = self.data_points[0]["R"]
        for i in range(1, len(self.data_points)):
            p = self.data_points[i]["P"]
            r = self.data_points[i]["R"]
            if p > best_p + eps:
                best_i, best_p, best_r = i, p, r
            elif abs(p - best_p) <= eps and r < best_r:
                best_i, best_r = i, r
        return best_i

    # ── 记录数据（弹窗手动输入 U、I）──

    def _record_point(self):
        R = self.r_value
        if R <= 0:
            self._show_toast("请先将电阻箱调到大于 0 的值")
            return

        for dp in self.data_points:
            if abs(dp["R"] - R) < 1e-6:
                self._show_toast("已存在 R={:g} Ω 的数据，不可重复记录！".format(R))
                return

        dialog = _ManualInputDialog(self.frame.winfo_toplevel(), R)
        self.frame.winfo_toplevel().wait_window(dialog.top)
        if dialog.result is None:
            return
        U_val, I_val = dialog.result

        P_val = U_val * I_val  # mW

        point = {"R": R, "U": U_val, "I": I_val, "P": P_val}
        self.data_points.append(point)

        idx = len(self.data_points)
        self.tree.insert("", "end", values=(
            idx, "{:g}".format(R), "{:.3f}".format(U_val),
            "{:.3f}".format(I_val), "{:.3f}".format(P_val)
        ))

    # ── 删除选中行 ──

    def _delete_selected(self):
        sel = self.tree.selection()
        if not sel:
            self._show_toast("请先在表格中选中要删除的行")
            return
        for item_id in sel:
            vals = self.tree.item(item_id, "values")
            r_val = float(vals[1])
            self.data_points = [dp for dp in self.data_points
                                if abs(dp["R"] - r_val) > 1e-6]
            self.tree.delete(item_id)
        self._reindex_table()

    def _reindex_table(self):
        for i, item_id in enumerate(self.tree.get_children()):
            vals = list(self.tree.item(item_id, "values"))
            vals[0] = i + 1
            self.tree.item(item_id, values=vals)

    def _show_toast(self, msg):
        toast = tk.Toplevel(self.frame.winfo_toplevel())
        toast.overrideredirect(True)
        toast.configure(bg="#ff4444")
        x = self.frame.winfo_rootx() + self.frame.winfo_width() // 2 - 150
        y = self.frame.winfo_rooty() + 80
        toast.geometry("300x36+{}+{}".format(x, y))
        tk.Label(toast, text=msg, bg="#ff4444", fg="#fff",
                 font=("Microsoft YaHei", 10, "bold")).pack(expand=True, fill=tk.BOTH)
        toast.after(2500, toast.destroy)

    def _clear_data(self):
        self.data_points.clear()
        for item_id in self.tree.get_children():
            self.tree.delete(item_id)
        self.ax1.clear()
        self._style_ax(self.ax1, title="伏安特性曲线", xlabel="U (V)", ylabel="I (mA)")
        self.canvas1.draw_idle()
        self.ax2.clear()
        self._style_ax(self.ax2, title="功率输出曲线", xlabel="R (Ω)", ylabel="P (mW)")
        self.canvas2.draw_idle()

    def _load_standard_data(self):
        data = get_experimental_data()["iv_data"]
        self._clear_data()
        for r, u, i in zip(data["R"], data["U"], data["I"]):
            # 标准数据中含短路和近开路点，保留用于分析。
            p = u * i
            point = {"R": float(r), "U": float(u), "I": float(i), "P": float(p)}
            self.data_points.append(point)
            idx = len(self.data_points)
            self.tree.insert("", "end", values=(
                idx, "{:g}".format(r), "{:.3f}".format(u),
                "{:.3f}".format(i), "{:.3f}".format(p)
            ))
        ok, msg = self._validate_exp1_data()
        if not ok:
            self._show_toast("标准数据校验失败: " + msg)
            return
        self._draw_plot()
        self._show_toast("已导入 {} 组标准数据并通过校验".format(len(self.data_points)))

    def _validate_exp1_data(self):
        if not self.data_points:
            return False, "无数据"
        for dp in self.data_points:
            if dp["R"] < 0 or dp["U"] < 0 or dp["I"] < 0:
                return False, "存在负值"
            if dp["U"] > 10 or dp["I"] > 200:
                return False, "超出量程"
            if abs(dp["P"] - dp["U"] * dp["I"]) > 1e-9:
                return False, "功率计算错误"
        return True, "ok"

    # ── 绘图（≥10 组才绘图）──

    def _draw_plot(self):
        if len(self.data_points) < 10:
            self._show_toast("需要至少 10 组数据才能绘图！当前 {} 组".format(len(self.data_points)))
            return

        Us = [d["U"] for d in self.data_points]
        Is = [d["I"] for d in self.data_points]
        Rs = [d["R"] for d in self.data_points]
        Ps = [d["P"] for d in self.data_points]

        # ── 图1：伏安特性曲线 (I vs U) ──
        self.ax1.clear()
        self._style_ax(self.ax1, title="伏安特性曲线", xlabel="U (V)", ylabel="I (mA)")
        order_u = np.argsort(Us)
        Us_sorted = [Us[i] for i in order_u]
        Is_sorted = [Is[i] for i in order_u]
        self.ax1.plot(Us_sorted, Is_sorted, "o-", color=ACCENT, linewidth=2,
                      markersize=5, label="I-U")
        max_p_idx = self._best_point_index()
        self.ax1.plot(Us[max_p_idx], Is[max_p_idx], "v", color="#ff4444",
                      markersize=10, zorder=5, label="MPP")
        self.ax1.legend(loc="upper right", fontsize=8, framealpha=0.4,
                        labelcolor=FG, prop=plt_font)
        self.fig1.tight_layout()
        self.canvas1.draw_idle()

        # ── 图2：功率输出曲线 (P vs R) ──
        self.ax2.clear()
        self._style_ax(self.ax2, title="功率输出曲线", xlabel="R (Ω)", ylabel="P (mW)")
        order_r = np.argsort(Rs)
        Rs_sorted = [Rs[i] for i in order_r]
        Ps_sorted = [Ps[i] for i in order_r]

        # 电阻跨度过大时自动使用对数横轴，避免小电阻区被压缩
        positive_rs = [r for r in Rs_sorted if r > 0]
        use_log_x = False
        if len(positive_rs) >= 2:
            r_min = min(positive_rs)
            r_max = max(positive_rs)
            use_log_x = (r_min > 0) and (r_max / r_min >= 30)
        if use_log_x:
            self.ax2.set_xscale("log")
            self.ax2.set_xlabel("R (Ω, log)", fontproperties=plt_font, color=FG, fontsize=9)

        self.ax2.plot(Rs_sorted, Ps_sorted, "s-", color=ACCENT2, linewidth=2,
                      markersize=5, label="P-R")
        self.ax2.plot(Rs[max_p_idx], Ps[max_p_idx], "v", color="#ff4444",
                      markersize=10, zorder=5, label="MPP")
        self.ax2.legend(loc="upper right", fontsize=8, framealpha=0.4,
                        labelcolor=FG, prop=plt_font)
        self.fig2.tight_layout()
        self.canvas2.draw_idle()

    # ── 数据分析弹窗 ──

    def _show_analysis(self):
        if len(self.data_points) < 10:
            self._show_toast("需要至少 10 组数据才能分析！当前 {} 组".format(len(self.data_points)))
            return

        best_idx = self._best_point_index()
        best = self.data_points[best_idx]
        max_p = best["P"]

        R0 = best["R"]
        Um = best["U"]
        Im = best["I"]

        # 仅使用已记录实测点做分析，不做任何拟合/外推：
        # Uoc_exp: 取最大电阻实测点电压（最接近开路）
        # Isc_exp: 取最小电阻实测点电流（最接近短路）
        nonzero_r = [d for d in self.data_points if d["R"] > 0]
        if nonzero_r:
            max_r_point = max(nonzero_r, key=lambda d: d["R"])
        else:
            max_r_point = max(self.data_points, key=lambda d: d["U"])
        min_r_point = min(self.data_points, key=lambda d: d["R"])
        Uoc_exp = max_r_point["U"]
        Isc_exp = min_r_point["I"]
        # FF = Pmax / (Uoc × Isc)，单位：mW / (V × mA) = 无量纲
        FF = max_p / (Uoc_exp * Isc_exp) if (Uoc_exp * Isc_exp) > 0 else 0

        win = tk.Toplevel(self.frame.winfo_toplevel())
        win.title("数据分析结果")
        win.configure(bg=BG)
        win.geometry("520x440")
        win.resizable(False, False)

        tk.Label(win, text="数据分析结果", bg=ACCENT, fg="#fff",
                 font=("Microsoft YaHei", 14, "bold")).pack(fill=tk.X, ipady=8)
        tk.Label(win, text="基于 {} 组实验数据".format(len(self.data_points)),
                 bg=BG, fg="#888", font=("Microsoft YaHei", 10)).pack(pady=(10, 16))
        tk.Label(win, text="计算仅使用已记录实测点，不进行拟合或外推",
                 bg=BG, fg="#aaa", font=("Microsoft YaHei", 9)).pack(pady=(0, 10))

        table = tk.Frame(win, bg=PANEL_BG)
        table.pack(fill=tk.X, padx=30)

        results = [
            ("最佳负载电阻 R₀", "{:g} Ω".format(R0)),
            ("最佳工作电压 Uₘ", "{:.3f} V".format(Um)),
            ("最佳工作电流 Iₘ", "{:.3f} mA".format(Im)),
            ("最大输出功率 Pₘₐₓ", "{:.3f} mW".format(max_p)),
            ("开路电压 Uoc (实测点近似)", "{:.3f} V".format(Uoc_exp)),
            ("短路电流 Isc (实测点近似)", "{:.3f} mA".format(Isc_exp)),
            ("填充因子 F·F", "{:.4f}".format(FF)),
        ]

        for i, (label, value) in enumerate(results):
            bg_c = "#1a2a3e" if i % 2 == 0 else "#16213e"
            row = tk.Frame(table, bg=bg_c)
            row.pack(fill=tk.X, ipady=6)
            tk.Label(row, text="  " + label, bg=bg_c, fg=FG,
                     font=("Microsoft YaHei", 11), anchor="w").pack(side=tk.LEFT)
            tk.Label(row, text=value + "  ", bg=bg_c, fg=ACCENT2,
                     font=("Consolas", 13, "bold"), anchor="e").pack(side=tk.RIGHT)

        tk.Label(win, text="", bg=BG).pack(pady=8)
        tk.Button(win, text="关闭", bg="#644", fg="#fff",
                  font=("Microsoft YaHei", 10), relief=tk.FLAT,
                  activebackground="#855",
                  command=win.destroy).pack(ipady=4, padx=20)

    def _get_current_params(self):
        p = dict(self.params)
        base_Iph = DEFAULT_PARAMS["single"]["Iph"]
        p["Iph"] = base_Iph * (self.light_intensity / 1000.0)
        return p


# ═══════════════════════════════════════════════
#  实验二、三：自动计算版本
# ═══════════════════════════════════════════════

class ExperimentTab:
    """实验二/三：自动计算 U、I、P。"""

    def __init__(self, parent_frame, title, experiment_type="distance"):
        self.frame = parent_frame
        self.title = title
        self.experiment_type = experiment_type
        self.params = {k: v for k, v in DEFAULT_PARAMS["single"].items()}
        self.data_points = []
        self.distance_cm = 30.0
        self.light_intensity = 1000.0
        self.fixed_R = 100.0
        self._build()

    def _build(self):
        left = tk.Frame(self.frame, bg=PANEL_BG, width=280)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 6))
        left.pack_propagate(False)
        right = tk.Frame(self.frame, bg=BG)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self._build_control(left)
        self._build_right(right)

    def _build_control(self, parent):
        # 电池类型（仅单晶硅，无选择）
        tk.Label(parent, text="电池类型", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 10, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        tf = tk.Frame(parent, bg=PANEL_BG)
        tf.pack(fill=tk.X, padx=10)
        self.cell_type_var = tk.StringVar(value="single")
        tk.Label(tf, text="单晶硅", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(side=tk.LEFT, padx=5)
        ttk.Separator(parent, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        if self.experiment_type == "distance":
            self._build_distance_control(parent)
        elif self.experiment_type == "light":
            self._build_light_control(parent)

        ttk.Separator(parent, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        # 实时读数
        tk.Label(parent, text="━━━ 实时读数 ━━━", bg=PANEL_BG, fg="#888",
                 font=("Consolas", 9)).pack(pady=(4, 6))
        self.reading_v = tk.Label(parent, text="U = 0.000 V", bg="#0a0a0a",
                                  fg="#00ff88", font=("Consolas", 16, "bold"),
                                  relief=tk.SUNKEN, bd=2, padx=8, pady=4)
        self.reading_v.pack(fill=tk.X, padx=10, pady=2)
        self.reading_i = tk.Label(parent, text="I = 0.000 mA", bg="#0a0a0a",
                                  fg="#00ff88", font=("Consolas", 16, "bold"),
                                  relief=tk.SUNKEN, bd=2, padx=8, pady=4)
        self.reading_i.pack(fill=tk.X, padx=10, pady=2)
        self.reading_p = tk.Label(parent, text="P = 0.000 mW", bg="#0a0a0a",
                                  fg="#ffcc00", font=("Consolas", 14, "bold"),
                                  relief=tk.SUNKEN, bd=2, padx=8, pady=4)
        self.reading_p.pack(fill=tk.X, padx=10, pady=2)

        ttk.Separator(parent, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        tk.Button(parent, text="● 记录当前数据点",
                  bg=ACCENT, fg="#fff", font=("Microsoft YaHei", 11, "bold"),
                  activebackground="#ff8855", relief=tk.FLAT,
                  command=self._record_point).pack(fill=tk.X, padx=10, pady=4, ipady=4)

        btn_frame = tk.Frame(parent, bg=PANEL_BG)
        btn_frame.pack(fill=tk.X, padx=10, pady=4)
        tk.Button(btn_frame, text="绘图", bg="#2a6", fg="#fff",
                  font=("Microsoft YaHei", 10), relief=tk.FLAT,
                  activebackground="#3b7",
                  command=self._draw_plot).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        tk.Button(btn_frame, text="清除数据", bg="#644", fg="#fff",
                  font=("Microsoft YaHei", 10), relief=tk.FLAT,
                  activebackground="#855",
                  command=self._clear_data).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)

    def _build_distance_control(self, parent):
        tk.Label(parent, text="━━━ 光源距离 ━━━", bg=PANEL_BG, fg=ACCENT,
                 font=("Microsoft YaHei", 10, "bold")).pack(anchor="w", padx=10, pady=(0, 2))
        self.dist_var = tk.DoubleVar(value=30.0)
        tk.Scale(parent, from_=5, to=100, orient=tk.HORIZONTAL,
                 variable=self.dist_var, bg=PANEL_BG, fg=FG,
                 troughcolor="#333", highlightthickness=0,
                 resolution=1, showvalue=True, length=200,
                 font=("Consolas", 9),
                 command=self._on_distance_change).pack(fill=tk.X, padx=10)
        self.dist_label = tk.Label(parent, text="d = 30 cm", bg=PANEL_BG, fg=FG,
                                   font=("Consolas", 12, "bold"))
        self.dist_label.pack(pady=4)
        info = tk.Frame(parent, bg=PANEL_BG)
        info.pack(fill=tk.X, padx=10, pady=4)
        tk.Label(info, text="固定条件:", bg=PANEL_BG, fg="#888",
                 font=("Microsoft YaHei", 9)).pack(anchor="w")
        tk.Label(info, text="  光源功率: 100 W", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(anchor="w")
        tk.Label(info, text="  负载电阻: 100 Ω", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(anchor="w")

    def _build_light_control(self, parent):
        tk.Label(parent, text="━━━ 光源功率 ━━━", bg=PANEL_BG, fg=ACCENT,
                 font=("Microsoft YaHei", 10, "bold")).pack(anchor="w", padx=10, pady=(0, 2))
        self.power_var = tk.DoubleVar(value=100.0)
        tk.Scale(parent, from_=10, to=300, orient=tk.HORIZONTAL,
                 variable=self.power_var, bg=PANEL_BG, fg=FG,
                 troughcolor="#333", highlightthickness=0,
                 resolution=5, showvalue=True, length=200,
                 font=("Consolas", 9),
                 command=self._on_power_change).pack(fill=tk.X, padx=10)
        self.power_label = tk.Label(parent, text="P_lamp = 100 W", bg=PANEL_BG, fg=FG,
                                    font=("Consolas", 12, "bold"))
        self.power_label.pack(pady=4)
        self.intensity_label = tk.Label(parent, text="E = 1000 W/m²", bg=PANEL_BG,
                                        fg="#aaa", font=("Consolas", 10))
        self.intensity_label.pack()
        info = tk.Frame(parent, bg=PANEL_BG)
        info.pack(fill=tk.X, padx=10, pady=4)
        tk.Label(info, text="固定条件:", bg=PANEL_BG, fg="#888",
                 font=("Microsoft YaHei", 9)).pack(anchor="w")
        tk.Label(info, text="  光源-板距离: 30 cm", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(anchor="w")
        tk.Label(info, text="  负载电阻: 100 Ω", bg=PANEL_BG, fg=FG,
                 font=("Microsoft YaHei", 9)).pack(anchor="w")

    def _build_right(self, parent):
        chart_frame = tk.Frame(parent, bg=BG)
        chart_frame.pack(fill=tk.BOTH, expand=True)
        self.fig = Figure(figsize=(6, 4), dpi=100, facecolor=BG)
        self.ax = self.fig.add_subplot(111)
        self._style_ax(self.ax)
        self.canvas = FigureCanvasTkAgg(self.fig, master=chart_frame)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)

        table_frame = tk.Frame(parent, bg=PANEL_BG, height=180)
        table_frame.pack(fill=tk.X, padx=0, pady=(4, 0))
        table_frame.pack_propagate(False)

        hdr = tk.Frame(table_frame, bg=PANEL_BG)
        hdr.pack(fill=tk.X, padx=8, pady=(4, 2))
        tk.Label(hdr, text="实验数据记录", bg=PANEL_BG, fg=ACCENT,
                 font=("Microsoft YaHei", 10, "bold")).pack(side=tk.LEFT)
        tk.Button(hdr, text="删除选中行", bg="#644", fg="#fff",
                  font=("Microsoft YaHei", 9), relief=tk.FLAT,
                  activebackground="#855",
                  command=self._delete_selected).pack(side=tk.RIGHT, padx=4)

        cols = ("序号", "自变量", "U (V)", "I (mA)", "P (mW)")
        self.tree = ttk.Treeview(table_frame, columns=cols, show="headings", height=6)
        for c in cols:
            self.tree.heading(c, text=c)
            w = 50 if c == "序号" else 100
            self.tree.column(c, width=w, anchor="center")
        vsb = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(8, 0))
        vsb.pack(side=tk.RIGHT, fill=tk.Y, padx=(0, 8))

    def _style_ax(self, ax, title="", xlabel="", ylabel=""):
        ax.set_facecolor("#0f0f23")
        ax.set_title(title, fontproperties=plt_font, color=FG, fontsize=12, pad=8)
        ax.set_xlabel(xlabel, fontproperties=plt_font, color=FG, fontsize=10)
        ax.set_ylabel(ylabel, fontproperties=plt_font, color=FG, fontsize=10)
        ax.tick_params(colors="#888", labelsize=8)
        for spine in ax.spines.values():
            spine.set_color(GRID_COLOR)
        ax.grid(True, alpha=0.2, color=GRID_COLOR)

    def _on_type_change(self):
        t = self.cell_type_var.get()
        self.params = {k: v for k, v in DEFAULT_PARAMS[t].items()}
        self._update_reading()

    def _on_distance_change(self, val):
        d = float(val)
        self.distance_cm = d
        self.dist_label.config(text="d = {:.0f} cm".format(d))
        self._update_reading()

    def _on_power_change(self, val):
        p = float(val)
        self.light_intensity = calc_light_intensity(self.distance_cm)
        self.power_label.config(text="P_lamp = {:.0f} W".format(p))
        self.intensity_label.config(text="E = {:.0f} W/m²".format(self.light_intensity))
        self._update_reading()

    def _get_current_params(self):
        p = dict(self.params)
        base_Iph = DEFAULT_PARAMS["single"]["Iph"]
        p["Iph"] = base_Iph * (self.light_intensity / 1000.0)
        return p

    def _update_reading(self):
        R = self.fixed_R
        if R <= 0:
            return
        try:
            p = self._get_current_params()
            V, I, P = solve_operating_point(p, R)
            self.reading_v.config(text="U = {:.3f} V".format(V))
            self.reading_i.config(text="I = {:.3f} mA".format(I * 1000))
            self.reading_p.config(text="P = {:.3f} mW".format(P * 1000))
        except Exception:
            self.reading_v.config(text="U = --- V")
            self.reading_i.config(text="I = --- mA")
            self.reading_p.config(text="P = --- mW")

    def _record_point(self):
        if self.experiment_type == "distance":
            var_val = self.distance_cm
            var_name = "d"
        else:
            var_val = self.light_intensity
            var_name = "E"

        for dp in self.data_points:
            if abs(dp["var_val"] - var_val) < 1e-6:
                self._show_toast("已存在 {}={:g} 的数据，不可重复记录！".format(var_name, var_val))
                return

        try:
            p = self._get_current_params()
            V, I, P = solve_operating_point(p, self.fixed_R)
        except Exception:
            return

        point = {"var_name": var_name, "var_val": var_val, "V": V, "I": I, "P": P}
        self.data_points.append(point)

        idx = len(self.data_points)
        var_str = "{:.1f}".format(var_val)
        self.tree.insert("", "end", values=(
            idx, var_str, "{:.3f}".format(V),
            "{:.3f}".format(I * 1000), "{:.3f}".format(P * 1000)
        ))
        self._draw_plot()

    def _delete_selected(self):
        sel = self.tree.selection()
        if not sel:
            self._show_toast("请先在表格中选中要删除的行")
            return
        for item_id in sel:
            vals = self.tree.item(item_id, "values")
            var_val = float(vals[1])
            self.data_points = [dp for dp in self.data_points
                                if abs(dp["var_val"] - var_val) > 1e-6]
            self.tree.delete(item_id)
        self._reindex_table()
        self._draw_plot()

    def _reindex_table(self):
        for i, item_id in enumerate(self.tree.get_children()):
            vals = list(self.tree.item(item_id, "values"))
            vals[0] = i + 1
            self.tree.item(item_id, values=vals)

    def _show_toast(self, msg):
        toast = tk.Toplevel(self.frame.winfo_toplevel())
        toast.overrideredirect(True)
        toast.configure(bg="#ff4444")
        x = self.frame.winfo_rootx() + self.frame.winfo_width() // 2 - 150
        y = self.frame.winfo_rooty() + 80
        toast.geometry("300x36+{}+{}".format(x, y))
        tk.Label(toast, text=msg, bg="#ff4444", fg="#fff",
                 font=("Microsoft YaHei", 10, "bold")).pack(expand=True, fill=tk.BOTH)
        toast.after(2000, toast.destroy)

    def _clear_data(self):
        self.data_points.clear()
        for item_id in self.tree.get_children():
            self.tree.delete(item_id)
        self.ax.clear()
        self._style_ax(self.ax)
        self.canvas.draw_idle()

    def _draw_plot(self):
        if not self.data_points:
            return
        self.ax.clear()
        var_name = self.data_points[0]["var_name"]
        var_vals = [d["var_val"] for d in self.data_points]
        Is = [d["I"] * 1000 for d in self.data_points]
        Ps = [d["P"] * 1000 for d in self.data_points]

        order = np.argsort(var_vals)
        var_vals = [var_vals[i] for i in order]
        Is = [Is[i] for i in order]
        Ps = [Ps[i] for i in order]

        self.ax.plot(var_vals, Is, "o-", color=ACCENT, linewidth=2,
                     markersize=6, label="I (mA)")
        self.ax.set_xlabel(var_name, fontproperties=plt_font, color=FG, fontsize=10)
        self.ax.set_ylabel("I (mA)", fontproperties=plt_font, color=ACCENT, fontsize=10)
        self.ax.tick_params(axis="y", labelcolor=ACCENT)

        ax2 = self.ax.twinx()
        ax2.plot(var_vals, Ps, "s--", color=ACCENT2, linewidth=2,
                 markersize=6, label="P (mW)")
        ax2.set_ylabel("P (mW)", fontproperties=plt_font, color=ACCENT2, fontsize=10, labelpad=10)
        ax2.tick_params(axis="y", labelcolor=ACCENT2)
        for spine in ax2.spines.values():
            spine.set_color(GRID_COLOR)
        p_max = max(Ps) if Ps else 1
        ax2.set_ylim(0, p_max * 1.25)

        max_idx = np.argmax(Ps)
        self.ax.plot(var_vals[max_idx], Is[max_idx], "v", color="#ff4444",
                     markersize=12, zorder=5)
        ax2.plot(var_vals[max_idx], Ps[max_idx], "v", color="#ff4444",
                 markersize=12, zorder=5)
        mpp_text = "MPP\n{:.1f}, {:.1f} mW".format(var_vals[max_idx], Ps[max_idx])
        self.ax.annotate(mpp_text,
                         xy=(var_vals[max_idx], Is[max_idx]),
                         xytext=(20, 20), textcoords="offset points",
                         color="#ff4444", fontsize=9, fontproperties=plt_font,
                         arrowprops=dict(arrowstyle="->", color="#ff4444"),
                         bbox=dict(boxstyle="round,pad=0.3", fc="#1a1a2e", ec="#ff4444", alpha=0.8))

        self.ax.set_title("实验数据 - " + self.title, fontproperties=plt_font,
                          color=FG, fontsize=12, pad=8)
        lines1, labels1 = self.ax.get_legend_handles_labels()
        lines2, labels2 = ax2.get_legend_handles_labels()
        self.ax.legend(lines1 + lines2, labels1 + labels2,
                       loc="upper center", bbox_to_anchor=(0.5, 1.02),
                       ncol=2, fontsize=9, framealpha=0.4,
                       labelcolor=FG, prop=plt_font)
        self.fig.tight_layout()
        self.canvas.draw_idle()


# ═══════════════════════════════════════════════
#  主应用
# ═══════════════════════════════════════════════

class SolarCellApp:
    def __init__(self, root):
        self.root = root
        self.root.title("太阳能电池伏安特性虚拟实验台")
        self.root.geometry("1250x800")
        self.root.configure(bg=BG)
        self.root.minsize(1050, 680)
        self._build_ui()

    def _build_ui(self):
        header = tk.Frame(self.root, bg=ACCENT, height=44)
        header.pack(fill=tk.X)
        header.pack_propagate(False)
        tk.Label(header, text="太阳能电池伏安特性虚拟实验台",
                 bg=ACCENT, fg="#fff",
                 font=("Microsoft YaHei", 14, "bold")).pack(side=tk.LEFT, padx=15)
        tk.Label(header, text="单二极管等效电路模型 / 半自动实验模式",
                 bg=ACCENT, fg="#ffe0cc",
                 font=("Microsoft YaHei", 10)).pack(side=tk.LEFT, padx=10)

        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        tab1 = tk.Frame(self.notebook, bg=BG)
        self.notebook.add(tab1, text=" 实验一：改变电阻 ")
        self.exp1 = ExperimentOneTab(tab1)

        tab2 = tk.Frame(self.notebook, bg=BG)
        self.notebook.add(tab2, text=" 实验二：改变距离 ")
        self.exp2 = ExperimentTab(tab2, "改变光源距离", experiment_type="distance")

        tab3 = tk.Frame(self.notebook, bg=BG)
        self.notebook.add(tab3, text=" 实验三：改变光强 ")
        self.exp3 = ExperimentTab(tab3, "改变光源功率", experiment_type="light")


def run():
    root = tk.Tk()
    app = SolarCellApp(root)
    root.mainloop()


if __name__ == "__main__":
    run()
