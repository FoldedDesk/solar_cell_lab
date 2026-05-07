"""
太阳能电池物理模型 — 单二极管等效电路模型
支持单片电池和多片串联组件
"""

import numpy as np
from scipy.optimize import fsolve

# 物理常数
Q = 1.602e-19    # 电子电荷 (C)
K = 1.381e-23    # 玻尔兹曼常数 (J/K)

# 默认参数（单片电池参数）
DEFAULT_PARAMS = {
    "single": {
        "name": "单晶硅",
        "N_cells": 4,     # 串联电池片数
        "Iph": 0.0275,    # 光生电流 (A)
        "I0": 2e-10,      # 反向饱和电流 (A)
        "Rs": 0.12,       # 单片串联电阻 (Ω)
        "Rsh": 200,       # 单片并联电阻 (Ω)
        "n": 1.5,         # 理想因子
    },
}


def diode_current_cell(V_cell, I, params, T=298.15):
    """单片电池方程"""
    Iph = params["Iph"]
    I0 = params["I0"]
    Rs = params["Rs"]
    Rsh = params["Rsh"]
    n = params["n"]
    Vt = n * K * T / Q
    return Iph - I0 * (np.exp((I * Rs + V_cell) / Vt) - 1) - (I * Rs + V_cell) / Rsh - I


def solve_iv_curve(params, T=298.15, n_points=200):
    """
    求解组件 I-V 曲线（多片串联）。
    返回 (V_array, I_array, P_array)，单位：V, A, W
    """
    N = params.get("N_cells", 1)

    # 先求单片 Voc，再乘以 N
    Voc_cell = solve_voc_cell(params, T)
    Voc = Voc_cell * N
    V_arr = np.linspace(0, Voc * 1.02, n_points)
    I_arr = np.zeros_like(V_arr)
    I_guess = params["Iph"]

    for i, v in enumerate(V_arr):
        v_cell = v / N  # 每片分到的电压

        def func(i_val):
            return diode_current_cell(v_cell, i_val, params, T)

        sol = fsolve(func, I_guess, full_output=True)
        i_val = sol[0][0]
        if i_val < 0:
            sol = fsolve(func, 0.001, full_output=True)
            i_val = sol[0][0]
        I_arr[i] = max(i_val, 0)
        I_guess = I_arr[i]

    P_arr = V_arr * I_arr
    return V_arr, I_arr, P_arr


def solve_voc_cell(params, T=298.15):
    """求单片电池开路电压"""
    Vt = params["n"] * K * T / Q
    Iph = params["Iph"]
    I0 = params["I0"]
    Rsh = params["Rsh"]
    Voc_approx = Vt * np.log(Iph / I0 + 1)

    def func(v):
        return Iph - I0 * (np.exp(v / Vt) - 1) - v / Rsh

    sol = fsolve(func, Voc_approx)
    return max(sol[0], 0)


def solve_voc(params, T=298.15):
    """求组件开路电压"""
    N = params.get("N_cells", 1)
    return solve_voc_cell(params, T) * N


def solve_isc(params, T=298.15):
    """求短路电流（串联组件电流等于单片电流）"""
    Vt = params["n"] * K * T / Q
    Iph = params["Iph"]
    I0 = params["I0"]
    Rs = params["Rs"]
    Rsh = params["Rsh"]

    def func(i_val):
        return Iph - I0 * (np.exp(i_val * Rs / Vt) - 1) - i_val * Rs / Rsh - i_val

    sol = fsolve(func, params["Iph"])
    return max(sol[0], 0)


def calc_fill_factor(Isc, Voc, Pmax):
    """填充因子 FF = Pmax / (Isc * Voc)"""
    if Isc * Voc == 0:
        return 0
    return Pmax / (Isc * Voc)


def find_mpp(V_arr, I_arr, P_arr):
    """最大功率点"""
    idx = np.argmax(P_arr)
    return V_arr[idx], I_arr[idx], P_arr[idx]


def calc_light_intensity(distance_cm):
    """根据光源距离估算光强 (W/m²)"""
    a = 1.8e5
    b = -1.8
    return a * (distance_cm ** b)


def get_experimental_data():
    """实验报告中的实测数据（单晶硅，光强约 242 W/m²）"""
    return {
        "iv_data": {
            "R": [0, 7, 15, 23, 32, 40, 49, 56, 65, 73, 82, 99, 159, 9999],
            "U": [0.00, 0.20, 0.40, 0.60, 0.80, 1.00, 1.20, 1.40,
                  1.60, 1.80, 2.00, 2.20, 2.40, 2.55],
            "I": [25.2, 25.5, 24.8, 24.7, 24.5, 24.3, 24.3, 24.5,
                  24.4, 24.7, 24.2, 22.0, 15.1, 0.2],
        },
        "Isc_mA": 25.2,
        "Uoc_V": 2.55,
        "FF": 0.75,
        "R0_ohm": 82,
        "distance_data": {
            # 实验二：开路电压、短路电流与光强关系测（单晶硅）
            "d_cm": [10, 15, 20, 25, 30, 35, 40, 45, 50],
            "E_wm2": [1016.0, 460.0, 244.0, 153.8, 105.1, 79.0, 63.4, 49.7, 39.8],
            "Voc_V": [2.92, 2.80, 2.71, 2.63, 2.57, 2.51, 2.46, 2.41, 2.38],
            "Isc_mA": [106.5, 48.0, 25.0, 15.4, 10.6, 8.0, 6.1, 4.8, 3.9],
        },
    }


if __name__ == "__main__":
    params = DEFAULT_PARAMS["single"]
    V, I, P = solve_iv_curve(params)
    Isc = solve_isc(params)
    Voc = solve_voc(params)
    Vmpp, Impp, Pmax = find_mpp(V, I, P)
    FF = calc_fill_factor(Isc, Voc, Pmax)

    print("=== 单晶硅模型验证 ===")
    print(f"Isc  = {Isc*1000:.2f} mA   (实验值: 27.10 mA)")
    print(f"Voc  = {Voc:.3f} V     (实验值: 2.79 V)")
    print(f"Pmax = {Pmax*1000:.3f} mW")
    print(f"Vmpp = {Vmpp:.3f} V, Impp = {Impp*1000:.2f} mA")
    print(f"FF   = {FF:.3f}        (实验值: 0.715)")
