# 两轮自平衡小车 + 自动调平平台 技术方案（修订版）

> 基于 STM32F411 + MG996R 舵机 + HC-05 蓝牙的最终方案

---

## 0. 方案决策记录

| # | 决策项 | 选择 | 理由 |
|---|--------|------|------|
| 1 | 平台执行器 | MG996R 舵机（方案 A） | 预算优先，复杂度低 |
| 2 | 主控 MCU | STM32F411CEU6 | 硬件编码器模式、确定性强、价格低 |
| 3 | 遥控通信 | HC-05 蓝牙模块 | 串口透传，手机即控，10 元解决 |
| 4 | 仿真工具 | Python (numpy + matplotlib + scipy) | `pip install` 搞定，不额外装软件 |
| 5 | 平台驱动 | 无刷/FOC 不涉及 | 选了舵机后不需要 |

**核心取舍**：用平台精度（±1-2° vs ±0.1°）和响应速度（50Hz vs 200Hz）换取了低成本（~400 元 vs ~800 元）和低复杂度。乒乓球平衡不可行，但水杯/手机/日常物品的防倾倒完全够用。

---

## 目录

1. [项目概述](#1-项目概述)
2. [系统架构](#2-系统架构)
3. [硬件设计](#3-硬件设计)
4. [控制算法](#4-控制算法)
5. [Python 仿真](#5-python-仿真)
6. [固件架构](#6-固件架构)
7. [实施路线图](#7-实施路线图)
8. [BOM 清单](#8-bom-清单)
9. [引脚分配](#9-引脚分配)
10. [安全机制](#10-安全机制)
11. [风险与对策](#11-风险与对策)

---

## 1. 项目概述

### 1.1 目标

制作一台两轮自平衡小车，顶部安装一个双轴（pitch/roll）舵机驱动的调平平台。小车自主保持直立平衡并行驶；平台自动保持水平，使放置在上的物品（水杯、手机等）不滑落。

### 1.2 核心指标

| 指标 | 目标值 | 说明 |
|------|:------:|------|
| 小车平衡 | 稳定直立，支持前进/后退/转向 | 串级 PID |
| 平台精度 | ±2° | 舵机死区限制，实测基准 |
| 平台承重 | ≥500g | MG996R 堵转扭矩 10 kg·cm |
| 控制周期（小车） | 200-500 Hz (2-5 ms) | STM32F411 完全胜任 |
| 控制周期（平台） | 50 Hz (20 ms) | 受舵机 PWM 刷新率限制 |
| 续航 | ≥30 分钟 | 3S 2200mAh LiPo |
| 遥控距离 | ≥10m | HC-05 蓝牙 |
| 整车重量 | ≤1.5kg（含电池不含负载） | 越轻越好控制 |

### 1.3 系统框图

```
                      ┌──────────────┐
                      │  上层负载     │  ← 水杯/手机/瓶/球
                      └──────┬───────┘
                             │
                      ┌──────┴───────┐
  平台 IMU(上) ──────►│ 双轴舵机平台  │  50Hz PID 控制
                      │ pitch+roll   │  MG996R × 2
                      └──────┬───────┘
                             │ 机械硬连接
                      ┌──────┴───────┐
  车体 IMU(下) ──────►│ 两轮平衡车体  │  200-500Hz 串级PID
                      │ (倒立摆)      │  N20 电机 × 2
                      │ STM32F411    │
                      │ HC-05 蓝牙    │  ← 手机遥控
                      └──────┬───────┘
                             │
                        ○───┴───○
                     左轮      右轮
```

---

## 2. 系统架构

### 2.1 控制层级（单 MCU 单核）

与原始方案不同，使用单颗 STM32F411CEU6。舵机控制非常简单（仅 PWM 输出），不需要独立 MCU 或独立核。

```
┌────────────────────────────────────────────────────────┐
│                    主控制循环 (SysTick 中断)              │
│                                                         │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│  │ 小车平衡环   │   │ 平台调平环   │   │ 运动控制环   │   │
│  │ 200-500Hz   │   │ 50Hz        │   │ (遥控解析)   │   │
│  │ 串级 PID    │   │ 独立 PID    │   │             │   │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   │
│         └─────────────────┼─────────────────┘          │
│                           ▼                             │
│                    ┌─────────────┐                      │
│                    │  传感器融合   │                      │
│                    │ 互补/卡尔曼  │                      │
│                    └─────────────┘                      │
│                           │                             │
│                    ┌──────┴──────┐                      │
│                    │  底层驱动    │                      │
│                    │ PWM/I2C/    │                      │
│                    │ Encoder/UART│                      │
│                    └─────────────┘                      │
└────────────────────────────────────────────────────────┘
```

### 2.2 频域解耦

舵机 50Hz vs 小车 200-500Hz，频率差 4-10 倍，天然解耦：

```
频段隔离：
   小车平衡：       慢速大扭矩       10-30 Hz（响应频段）
   平台调平：       快速微调          50 Hz（纠正频段）
```

平台在每个小车摆动周期（~30-50ms）内至少响应 2-3 次，能有效补偿小车摆动带来的基座倾斜。

### 2.3 通信架构

```
手机 ──[蓝牙 BLE 2.0]──▶ HC-05 ──[UART]──▶ STM32F411
                                                 │
                    串口调试 ◀──[UART]── USB-TTL ◀── 电脑 (Python 可视化)
```

两条 UART 独立：UART1→HC-05 蓝牙遥控，UART2→USB-TTL 调试/数据输出。

---

## 3. 硬件设计

### 3.1 MCU: STM32F411CEU6

选型理由：
- **硬件编码器模式**：定时器的 Encoder Mode 直接用硬件读取 AB 相编码器脉冲，不丢数，不占 CPU。ESP32 只能用 GPIO 中断模拟，高速下会漏脉冲——这对速度环精度至关重要。
- **48 引脚 LQFP / 最小系统板**：焊接友好，市面开发板 ~25 元
- **100MHz Cortex-M4 + FPU**：带硬件浮点单元，PID 计算和卡尔曼滤波都用 float 算，无压力
- **5 个独立定时器**：≥4 路 PWM + 2 路编码器 + SysTick → 刚好够

> **可替换型号**：STM32F103C8T6（~15 元，72MHz，依然够用）、STM32F303CCT6（~30 元，带 FPU）、STM32G431KBU6（~35 元）。只要满足外设数量，替换后只改引脚配置。

### 3.2 蓝牙: HC-05

- UART 串口透传，波特率 9600/115200
- 工作在从机模式，手机连接后映射为虚拟串口
- STM32 端就是 `HAL_UART_Receive()` 读指令，`HAL_UART_Transmit()` 发数据
- **各种 HC-05/HC-06/JDY-31/JDY-33（HC-05 兼容系列）都通用**——只要支持 AT 指令配波特率即可

### 3.3 平台执行器: MG996R 舵机

MG996R 关键参数（实际测量，非标称）：
- 堵转扭矩：~10 kg·cm（6V 供电）
- 响应速度：~0.17s/60°（6V），即一个 20°步进需 ~55ms
- **死区：±1-2°** ← 这是平台精度的真实上限
- PWM 频率：50Hz（周期 20ms），脉宽 500-2500μs 对应 0-180°
- 供电：5-6V，峰值电流 ~2A/个

**注意**：舵机不宜频繁、微小、连续调节——会发热、磨损。PID 输出要加死区：误差 <2° 时不输出。

### 3.4 IMU: MPU6050 × 2

两个 MPU6050 模块（GY-521 小板）：
- 下部：贴车体，测车体倾角和角速度
- 上部：贴平台面板，测平台相对大地的角度

**I2C 地址冲突处理**：MPU6050 默认 I2C 地址 0x68。挂两个的方法有二：

| 方法 | 操作 | 推荐度 |
|------|------|:---:|
| A. AD0 脚不同电平 | 一个 AD0→GND (0x68)，另一个 AD0→VCC (0x69) | ⭐⭐⭐ |
| B. 两路 I2C | 用 STM32 的两组 I2C 分别接 | ⭐⭐ |
| C. I2C MUX | 加一片 TCA9548A | ❌（杀鸡用牛刀） |

**推荐方法 A**：GY-521 模块上有 AD0 焊盘，一个悬空（默认 GND），另一个焊到 VCC。只改一个焊点。

### 3.5 动力系统

- **电机**：N20 直流减速电机，100 RPM，1:50 减速比，自带 AB 相霍尔编码器（分辨率：电机每圈 7 脉冲 × 50 = 车轮每圈 350 脉冲）。6V 额定。
- **驱动**：DRV8833 双路 H 桥模块，2A/通道，逻辑电压 3.3V 兼容。
- **轮子**：43mm 橡胶轮。

> **扭矩校验**：N20 100RPM 堵转扭矩约 15 kg·cm。1.5kg 整车 + 2.15cm 轮径(43mm) → 需要 ≥3.2 kg·cm。余量 4.7 倍，非常充裕。43mm 小轮子重心更低，对平衡控制有利。

### 3.6 电源

- **电池**：3S 2200mAh 30C LiPo（11.1V）
- **5V 输出**：LM2596 降压模块 → 供 STM32、HC-05、舵机（注意：两个 MG996R 峰值 4A，LM2596 额定 3A 略紧，加个 1000μF 电容缓冲，或换成 5A 的降压模块）
- **3.3V 输出**：AMS1117-3.3V LDO → 供两个 MPU6050

**电源预算（平均运行）：**

| 负载 | 功率 |
|------|:---:|
| STM32F411 (运行) | 0.3W |
| HC-05 | 0.1W |
| 2 × MPU6050 | 0.03W |
| 2 × N20 电机（平路平衡） | ~3W |
| 2 × MG996R（间歇工作） | ~1W |
| **合计** | **~4.5W** |

```
电池能量：11.1V × 2200mAh = 24.4 Wh
续航（平均）：24.4 / 4.5 ≈ 5.4 小时（理论最大）
实际续航（含峰值/损耗）：~40-60 分钟
```

> 30 分钟目标轻松达成。如果实际使用中续航不够，换 3S 3000mAh 电池（~100 元）。

---

## 4. 控制算法

### 4.1 传感器融合

#### MPU6050 初始校准（每次上电）

```python
# 伪代码 → 后续给你 C 代码
上电静止 2 秒：
    gyro_bias_x = mean(gyro_x_raw[0:2000])  # 500 次采样平均
    gyro_bias_y = mean(gyro_y_raw)
    gyro_bias_z = mean(gyro_z_raw)
    # 加速度计不需要零偏校准，但需要换算倾角
```

#### 互补滤波求角度

```python
# dt = 控制周期(秒)
# alpha = 0.96 (推荐起点，后续根据实际噪声微调)

angle = alpha * (angle + gyro_rate * dt) + (1 - alpha) * accel_angle
```

- `gyro_rate` = 陀螺仪原始值 - 零偏
- `accel_angle` = atan2(accel_y, accel_z)（测 pitch），atan2(accel_x, accel_z)（测 roll）
- `alpha = 0.96`：96% 信赖陀螺仪积分（短期可信），4% 信赖加速度计（长期可信）

> **进阶选项（后期优化）**：换成卡尔曼滤波。MPU6050 内置 DMP（Digital Motion Processor）也能直接输出融合后的四元数。先用互补滤波跑起来，跑通了再换不迟。

### 4.2 小车串级 PID

**为什么不只用一个 PID？**

单环 PID 从角度误差直接输出电机扭矩在慢速时可行，但加速/刹车时会振荡。串级 PID 让内环（角速度环）先稳，外环（角度环）再调，响应更快、超调更小。

```
目标角度(0°) ──→ [角度PID] ──→ [目标角速度]
                                  │
实际角速度 ◄───────────────────────┘
     │
     ▼
[角速度PID] ──→ [电机扭矩/PWM]
```

**完整 C 语言实现（带抗饱和、微分滤波、输出限幅）：**

```c
// === 数据结构 ===
typedef struct {
    // 参数
    float kp, ki, kd;
    float dt;
    float integral_limit;    // 积分限幅（防饱和）
    float output_limit;      // 输出限幅（保护电机）
    float lowpass_alpha;     // 微分项低通滤波系数
    
    // 状态
    float integral;
    float last_error;
    float last_derivative;   // 滤波后的微分
    
} PIDController;

// === 初始化 ===
void PID_Init(PIDController *pid, float kp, float ki, float kd,
              float dt, float i_limit, float out_limit, float lp_alpha) {
    pid->kp = kp;
    pid->ki = ki;
    pid->kd = kd;
    pid->dt = dt;
    pid->integral_limit = i_limit;
    pid->output_limit = out_limit;
    pid->lowpass_alpha = lp_alpha;
    pid->integral = 0.0f;
    pid->last_error = 0.0f;
    pid->last_derivative = 0.0f;
}

// === 计算 ===
float PID_Update(PIDController *pid, float setpoint, float measurement) {
    float error = setpoint - measurement;
    
    // P 项
    float P = pid->kp * error;
    
    // I 项（带积分限幅，防止 windup）
    pid->integral += error * pid->dt;
    if (pid->integral > pid->integral_limit)
        pid->integral = pid->integral_limit;
    else if (pid->integral < -pid->integral_limit)
        pid->integral = -pid->integral_limit;
    float I = pid->ki * pid->integral;
    
    // D 项（带低通滤波，抑制高频噪声）
    float raw_derivative = (error - pid->last_error) / pid->dt;
    float filtered_derivative = pid->lowpass_alpha * pid->last_derivative
                               + (1.0f - pid->lowpass_alpha) * raw_derivative;
    pid->last_derivative = filtered_derivative;
    float D = pid->kd * filtered_derivative;
    
    pid->last_error = error;
    
    // 合并输出并限幅
    float output = P + I + D;
    if (output > pid->output_limit)
        output = pid->output_limit;
    else if (output < -pid->output_limit)
        output = -pid->output_limit;
    
    return output;
}

// === 复位（模式切换时清零积分） ===
void PID_Reset(PIDController *pid) {
    pid->integral = 0.0f;
    pid->last_error = 0.0f;
    pid->last_derivative = 0.0f;
}
```

**小车 PID 参数初始值（仿真粗调 + 实物微调）：**

| 参数 | 角度环（外环） | 角速度环（内环） |
|------|:---:|:---:|
| Kp | 30.0 | 5.0 |
| Ki | 0.5 | 0.1 |
| Kd | 2.0 | 0.0 |
| 积分限幅 | ±50 | ±100 |
| 输出限幅 | ±200 | ±255（PWM 满量程） |
| 低通 α | - | 0.9 |

> 这些值来自经验公式，**仿真后会出更精确的起点**，实物上还需根据实际重心、电机、摩擦力微调。

**转向叠加：**

```c
// balance_output: 串级PID输出
// turn_output:    遥控转向指令 (范围归一化)
// speed_output:   速度环输出 (可选)

int16_t left_pwm  = balance_output + turn_output - speed_output;
int16_t right_pwm = balance_output - turn_output - speed_output;

// 限幅
left_pwm  = CLAMP(left_pwm,  -255, 255);
right_pwm = CLAMP(right_pwm, -255, 255);
```

### 4.3 平台 PID（双轴独立）

```
平台 IMU 测量角度 (pitch, roll)
        │
        ▼
小车基座倾角作为"目标角度"的反向输入
        │
        ▼
Pitch PID → 舵机1 PWM
Roll  PID → 舵机2 PWM
```

**两点不同**：
1. 目标不是绝对 0°，而是**小车倾斜的反方向**（基座前倾 5° → 平台要后仰 5° 来保持水平）
2. 因为小车平衡环也在调，平台感受到的是**已衰减的基座晃动**，而不是全量

```c
// 平台控制（50Hz）
void platform_control(void) {
    // 平台IMU测到的pitch/roll（补码滤波后）
    float plat_pitch = get_platform_pitch();
    float plat_roll  = get_platform_roll();
    
    // 小车IMU测到的pitch/roll
    float car_pitch  = get_car_pitch();
    float car_roll   = get_car_roll();
    
    // 平台误差 = 小车当前姿态的反向（这是平台需要补偿的量）
    float pitch_error = car_pitch - plat_pitch;  // 简化版
    float roll_error  = car_roll  - plat_roll;
    
    // 死区 ±2°，防舵机微振
    if (fabsf(pitch_error) < 2.0f) pitch_error = 0;
    if (fabsf(roll_error)  < 2.0f) roll_error  = 0;
    
    // PID 输出
    float pitch_out = PlatformPID_Update(&pid_pitch, 0.0f, pitch_error);
    float roll_out  = PlatformPID_Update(&pid_roll,  0.0f, roll_error);
    
    // 转为舵机 PWM 脉宽 (500-2500μs → 0-180°)
    // 中心位置 = 1500μs
    uint16_t servo1_pwm = 1500 + (int16_t)(pitch_out * 1000.0f / 90.0f);
    uint16_t servo2_pwm = 1500 + (int16_t)(roll_out  * 1000.0f / 90.0f);
    servo1_pwm = CLAMP(servo1_pwm, 500, 2500);
    servo2_pwm = CLAMP(servo2_pwm, 500, 2500);
    
    servo_set(0, servo1_pwm);
    servo_set(1, servo2_pwm);
}
```

**平台 PID 初始参数：**

| 参数 | 值 | 说明 |
|------|:---:|------|
| Kp | 15.0 | 比小车小——舵机不需要激进响应 |
| Ki | 1.0 | |
| Kd | 5.0 | |
| 死区 | ±2° | MG996R 死区水平 |
| 输出限幅 | ±45° | 不超出机械行程 |

### 4.4 前馈解耦

平台 PID 是"事后补偿"——等平台偏离水平了才纠正。加上前馈可以**提前预测**：

```c
// 前馈项：小车基座正在倾斜的速度 × 前馈系数
float feedforward = FF_GAIN * car_gyro_rate;
platform_output += feedforward;
```

- `car_gyro_rate`：小车 IMU 陀螺仪的角速度（告诉平台"基座在往哪边转"）
- `FF_GAIN = 0.2-0.3`：前馈量比 PID 小，起辅助作用

### 4.5 手动调参步骤（PID 调参口诀）

> 调参顺序：**角速度内环 → 角度外环 → 速度环 → 平台环**

**Step 1：角速度环**
```
1. Kd=Ki=0, Kp 从 1 开始逐渐增大
2. 手持车体快速来回摆动（模拟扰动）
3. 感受车轮是否有"抵抗旋转"的趋势
4. 加大 Kp 到车轮有力对抗但还不发抖
5. 加入 Ki=0.05-0.2 消除残余偏转
```

**Step 2：角度环**
```
1. 角速度环 Kp 调好后锁定
2. 车体放手让它倒，逐次加大角度环 Kp
3. 直到一松手车轮"冲"向倾倒方向（有力但不抖）
4. 加 Kd 抑制振荡（车体"硬邦邦"原地颤 = Kd 不够或 Kp 太大）
5. 加 Ki=0.3-0.8 让车体回到完全直立
```

**Step 3：平台环**
```
1. 小车先调好（能稳定直立 30 秒以上不动遥控）
2. 平台单独 PID 调通（固定在工作台上验证）
3. 装到小车上联调
4. 观察平台在小车晃动时的响应，Kp 从小开始加
```

---

## 5. Python 仿真

### 5.1 仿真目标

不烧硬件，在电脑上验证：
1. 倒立摆串级 PID 能否稳定
2. 平台 PID + 舵机延迟（20ms）对扰动响应
3. 两级耦合时频域解耦是否成立
4. 出 PID 参数初始值，上实物只微调

### 5.2 环境搭建（你来做）

```bash
# 1. 装 Python（已有就跳过）
# 官网 python.org → 下载 3.10+ → 安装

# 2. 装依赖（三个命令任选一个）
pip install numpy matplotlib scipy       # 基础方案
# 或
pip install numpy matplotlib scipy control  # 带控制系统工具箱(可选)

# 3. 验证
python -c "import numpy; import matplotlib; print('OK')"
```

> 仅需 `pip install` 三个包，不需要 MATLAB/Octave/任何付费软件。

### 5.3 仿真代码（我来写 → 你来跑）

我将分 3 个文件交付：

| 文件 | 内容 | 你做什么 |
|------|------|---------|
| `sim_cart.py` | 单轮倒立摆 + 串级 PID | `python sim_cart.py` → 看角度曲线 |
| `sim_platform.py` | 双轴平台 + 舵机延迟 | `python sim_platform.py` → 看响应曲线 |
| `sim_coupled.py` | 两级耦合模型 | `python sim_coupled.py` → 看解耦效果 |

每个文件运行后弹出一个 matplotlib 图表，横轴是时间，纵轴是角度/输出等。你可以改文件顶部的 PID 参数重跑，看曲线变化。

### 5.4 仿真模型（简化）

**小车（倒立摆）：**
```
状态：θ = 车体倾角, θ̇ = 车体角速度
输入：u = 电机扭矩 → 车轮加速度

θ̈ = (m·g·L·sinθ + u) / (I + m·L²)

其中：
  m  = 车体质量 (~1.0 kg)
  g  = 重力加速度 (9.81)
  L  = 重心到轮轴距离 (~0.05 m)
  I  = 转动惯量 (~0.01 kg·m²)
```

**平台（含舵机延迟）：**
```
舵机延迟建模为一阶惯性环节：
  τ·α̇ + α = u     (τ=20ms 时间常数)

平台动力学：
  α̈ = K_servo·(u - α)     (K_servo ≈ 50 rad/s² 舵机角加速度)
```

---

## 6. 固件架构

### 6.1 开发环境（PlatformIO）

| 步骤 | 谁来做 |
|------|:---:|
| 安装 VS Code | 你 |
| 在 VS Code 扩展商店搜 PlatformIO → 安装 | 你 |
| 创建新项目 → Board: STM32F411CE "BlackPill" → Framework: STM32Cube | 你 |
| platformio.ini 配置内容我写给你 | 我 → 你粘贴 |

**platformio.ini：**
```ini
[env:blackpill_f411ce]
platform = ststm32
board = blackpill_f411ce
framework = stm32cube
monitor_speed = 115200

lib_deps =
    tockn/MPU6050_tockn @ ^1.5.0

build_flags =
    -O2
    -DUSE_HAL_DRIVER
    -DSTM32F411xE
```

### 6.2 文件结构

```
auto-balancer-car/
├── firmware/
│   ├── src/
│   │   ├── main.cpp              # 主程序入口，初始化 + 主循环
│   │   ├── imu.cpp / imu.h       # MPU6050 驱动 + 互补滤波
│   │   ├── pid.cpp / pid.h       # PID 通用实现
│   │   ├── motor.cpp / motor.h   # 电机 PWM + 编码器读取
│   │   ├── servo.cpp / servo.h   # 舵机 PWM
│   │   ├── balance.cpp / balance.h  # 小车平衡逻辑
│   │   ├── platform.cpp / platform.h # 平台控制逻辑
│   │   ├── bluetooth.cpp / bluetooth.h # HC-05 指令解析
│   │   └── safety.cpp / safety.h # 安全监控
│   ├── include/
│   │   └── config.h              # 全局参数（PID值、引脚定义等）
│   └── platformio.ini
├── simulation/
│   ├── sim_cart.py
│   ├── sim_platform.py
│   └── sim_coupled.py
├── tools/
│   ├── calibrate.py              # 校准数据采集
│   └── plot_serial.py            # 实时串口数据可视化
└── docs/
    └── (本文件)
```

### 6.3 主循环设计

```c
// 定时器中断驱动的控制循环
// TIM6 中断 @ 500Hz (小车环)
// TIM7 中断 @ 50Hz  (平台环)

volatile uint8_t balance_flag = 0;   // 小车环就绪
volatile uint8_t platform_flag = 0;  // 平台环就绪

// TIM6 ISR: 500Hz
void TIM6_DAC_IRQHandler(void) {
    if (LL_TIM_IsActiveFlag_UPDATE(TIM6)) {
        LL_TIM_ClearFlag_UPDATE(TIM6);
        balance_flag = 1;   // 通知主循环：读IMU、跑PID、输出电机PWM
    }
}

// TIM7 ISR: 50Hz
void TIM7_IRQHandler(void) {
    if (LL_TIM_IsActiveFlag_UPDATE(TIM7)) {
        LL_TIM_ClearFlag_UPDATE(TIM7);
        platform_flag = 1;  // 通知主循环：跑平台PID
    }
}

// 主循环
int main(void) {
    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();
    MX_I2C1_Init();    // 车体IMU
    MX_I2C2_Init();    // 平台IMU (或同一路不同地址)
    MX_TIM1_Init();    // 左右轮 PWM
    MX_TIM2_Init();    // 左轮编码器输入
    MX_TIM3_Init();    // 右轮编码器输入
    MX_TIM4_Init();    // 舵机 PWM
    MX_TIM6_Init();    // 小车环定时器
    MX_TIM7_Init();    // 平台环定时器
    MX_USART1_UART_Init();  // HC-05 蓝牙
    MX_USART2_UART_Init();  // 调试串口

    imu_calibrate();  // 2秒静止校准

    HAL_TIM_Base_Start_IT(&htim6);
    HAL_TIM_Base_Start_IT(&htim7);

    while (1) {
        // --- 小车平衡环 (500Hz) ---
        if (balance_flag) {
            balance_flag = 0;
            
            // 1. 读车体IMU + 互补滤波 → angle, gyro_rate
            // 2. 读编码器 → speed, position
            // 3. 串级PID → motor_pwm
            // 4. 安全检测：倾角>45°? → 停电机
            // 5. 输出PWM
            
            balance_update();
        }
        
        // --- 平台调平环 (50Hz) ---
        if (platform_flag) {
            platform_flag = 0;
            
            // 1. 读平台IMU → platform_angle
            // 2. 读车体IMU → base_angle, base_gyro
            // 3. PID + 前馈 → servo_pwm
            // 4. 输出舵机PWM
            
            platform_update();
        }
        
        // --- 蓝牙遥控 (空闲处理) ---
        if (bluetooth_available()) {
            char cmd = bluetooth_read();
            parse_command(cmd);  // F/B/L/R/S(停)/T(微调参数)
            // 更新 target_speed / target_turn
        }
    }
}
```

### 6.4 蓝牙遥控协议

**手机端**：安装任意蓝牙串口 App（如 "Serial Bluetooth Terminal"，免费）

**指令格式**（单字符，简单可靠）：

| 指令 | 含义 |
|:---:|------|
| `F` | 前进 |
| `B` | 后退 |
| `L` | 左转 |
| `R` | 右转 |
| `S` | 停止 |
| `+` | 加速 |
| `-` | 减速 |
| `E` | 急停（电机断电） |
| `D` | 发送调试数据 |

> 后期可升级为手机 App 的虚拟摇杆（发送 "X,Y" 双轴坐标），但先用单字符跑起来。

---

## 7. 实施路线图

### 总体流程

```
Phase 0: 采购 + 环境搭建 (1-2周)
    │
Phase 1: Python仿真 (2-3天)
    │
Phase 2: 子系统独立验证 (2-3周)
    ├─ 2a: IMU 读数
    ├─ 2b: 电机 + 编码器
    ├─ 2c: 舵机控制
    ├─ 2d: 小车平衡 (不装平台)
    └─ 2e: 平台独立调平
    │
Phase 3: 集成联调 (1-2周)
    │
Phase 4: 优化 + 遥控 (1周)
```

---

### Phase 0：采购 + 环境搭建（1-2周）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 0.1 | 按 BOM 清单采购所有硬件 | 👤 你 | 见 §8 BOM 清单。淘宝下单选同一家店能省运费。 |
| 0.2 | 装 VS Code + PlatformIO 插件 | 👤 你 | 打开 VS Code → 扩展 → 搜 PlatformIO → 安装 |
| 0.3 | 装 Python + numpy/matplotlib/scipy | 👤 你 | `pip install numpy matplotlib scipy` |
| 0.4 | 3D 打印 / 加工结构件 | 👤 你 | 车架、平台面板、云台万向节、电机支架 |
| 0.5 | 硬件装配 | 👤 你 | 焊接排针、接线、安装电机/舵机/IMU/电池座 |
| 0.6 | 创建项目骨架 + platformio.ini | 🤖 我 | 我把完整项目目录和配置文件写好给你 |
| 0.7 | 测试烧录（点灯程序） | 👤 你 | 验证 STM32 能正常烧录运行 |

> **验收标准**：所有硬件到齐、装配完成、STM32 能烧录 Blink。

---

### Phase 1：Python 仿真（2-3 天）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 1.1 | `sim_cart.py` — 倒立摆串级 PID 仿真 | 🤖 我 | 我把代码写好给你 |
| 1.2 | 运行 + 改 PID 参数看曲线变化 | 👤 你 | 跑脚本，改参数，截图反馈 |
| 1.3 | `sim_platform.py` — 平台 + 舵机延迟仿真 | 🤖 我 | 同上 |
| 1.4 | 运行 + 看舵机延迟对响应的影响 | 👤 你 | 同上 |
| 1.5 | `sim_coupled.py` — 两级耦合仿真 | 🤖 我 | 同上 |
| 1.6 | 运行 + 验证频域解耦 | 👤 你 | 同上 |
| 1.7 | 我从仿真结果输出推荐 PID 初始值 | 🤖 我 | 根据你的仿真截图/反馈微调参数 |

> **验收标准**：仿真中小车和平台都能稳定，输出一套 PID 参数初值表。

---

### Phase 2：子系统独立验证（2-3 周）

#### 2a. IMU 读取 + 滤波（2-3 天）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 2a.1 | MPU6050 驱动代码（I2C 初始化、寄存器配置） | 🤖 我 | 用 HAL 库写，适配 STM32F411 |
| 2a.2 | 互补滤波代码 | 🤖 我 | 同上 |
| 2a.3 | 烧录，串口打印原始加速度/陀螺值 | 👤 你 | |
| 2a.4 | 晃动传感器，看值变化方向对不对 | 👤 你 | 反馈异常 |
| 2a.5 | 烧录含互补滤波的版本，打印融合角度 | 👤 你 | |
| 2a.6 | 校准程序（采集零偏 + 写入 EEPROM/Flash） | 🤖 我 | 每次上电自动校准 |
| 2a.7 | 两个 MPU6050 同时读 + 地址冲突验证 | 👤 你 | 确认 I2C 地址 0x68/0x69 各一个 |

> **验收标准**：串口打印的角度变化和实物倾斜一致，抖动 < 0.5°。

#### 2b. 电机 + 编码器（2-3 天）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 2b.1 | 电机 PWM 驱动代码（TIM1 四路 PWM） | 🤖 我 | |
| 2b.2 | 编码器模式代码（TIM2/TIM3 Encoder Mode） | 🤖 我 | 硬件直接读，不丢脉冲 |
| 2b.3 | 烧录，调 PWM 让电机慢速正反转 | 👤 你 | 验证接线和方向 |
| 2b.4 | 转电机，Serial 输出编码器计数 | 👤 你 | 验证方向和分辨率 |

> **验收标准**：PWM 能控制电机速度和方向，编码器计数方向和幅度正确。

#### 2c. 舵机控制（1 天）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 2c.1 | 舵机 PWM 代码（TIM4，50Hz） | 🤖 我 | |
| 2c.2 | 烧录，发指令让舵机转到 0°/90°/180° | 👤 你 | 验证行程和方向 |
| 2c.3 | 两个舵机同时工作 + 负载测试 | 👤 你 | 放本书在平台上，看能不能带得动 |

> **验收标准**：两路舵机能独立控制，0-180° 可调，能带动 500g 负载。

#### 2d. 小车平衡独立闭环（关键里程碑）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 2d.1 | 串级 PID 控制循环代码 | 🤖 我 | 含角度环 + 角速度环 + 速度环 |
| 2d.2 | 烧录，**先不装平台**，双手扶着车体测试 | 👤 你 | 感受车轮是否有"抵抗倾倒"的力 |
| 2d.3 | 逐渐放手，观察是否能短暂直立 | 👤 你 | 反馈现象 |
| 2d.4 | 根据你反馈调整 PID 参数（多轮迭代） | 🤖 我 ↔ 👤 你 | 最核心的协作环节 |
| 2d.5 | 车体能稳定直立 30 秒以上 | 👤 你 | ✅ 里程碑 |
| 2d.6 | 加入速度环 + 遥控前进后退转向 | 🤖 我 | |

> **验收标准**：小车在平地上能独立直立 ≥30 秒，遥控下能前进后退转向不倾倒。

#### 2e. 平台独立调平

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 2e.1 | 平台 PID 代码 | 🤖 我 | 含死区 |
| 2e.2 | **把平台固定在工作台上**（不装到小车上） | 👤 你 | 手动倾斜基座，观察平台能否保持水平 |
| 2e.3 | 反馈响应情况 + 调整参数 | 👤 你 ↔ 🤖 我 | |

> **验收标准**：倾斜基座时平台能在 0.5-1 秒内恢复水平。

---

### Phase 3：集成联调（1-2 周）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 3.1 | 把平台安装到小车上 | 👤 你 | 机械安装 |
| 3.2 | 联调代码（小车主循环 + 平台 + 前馈） | 🤖 我 | |
| 3.3 | 静态测试：小车直立时，放水杯到平台上 | 👤 你 | 看平台能否保持水杯不滑 |
| 3.4 | 动态测试：小车前进后退时平台的补偿效果 | 👤 你 | |
| 3.5 | 反馈耦合问题 + 调整参数 | 👤 你 ↔ 🤖 我 | |
| 3.6 | 颠簸/斜坡测试 | 👤 你 | 推动小车过障碍看平衡恢复 |

> **验收标准**：小车匀速行驶时平台上水杯稳定不滑，加减速时杯内水面晃动但杯子不倾倒。

---

### Phase 4：优化 + 遥控（1 周）

| # | 任务 | 谁做 | 详情 |
|---|------|:---:|------|
| 4.1 | 手机蓝牙串口 App → HC-05 通信验证 | 👤 你 | 发 F/B/L/R/S 测试 |
| 4.2 | 蓝牙遥控解析代码 | 🤖 我 | |
| 4.3 | 遥控行驶测试 | 👤 你 | |
| 4.4 | 调试串口数据输出 → Python 实时作图 | 🤖 我 | tools/plot_serial.py |
| 4.5 | 自动校准流程优化 | 🤖 我 | 如需要 |
| 4.6 | 安全机制完善 | 🤖 我 | |

> **验收标准**：手机遥控控制小车全方向行驶，平台自动保持水平。

---

## 8. BOM 清单

### 8.1 电子元器件（淘宝购买）

| # | 物品 | 推荐型号/关键词 | 数量 | 约¥ | 备注 |
|:-:|------|---------|:---:|:---:|------|
| 1 | MCU 开发板 | STM32F411CEU6 "BlackPill" | 1 | 25 | WeAct 或 RobotDyn 品牌 |
| 2 | 蓝牙模块 | HC-05 (或 HC-06/JDY-31) | 1 | 10 | 要 3.3V 版本的 |
| 3 | 6 轴 IMU | GY-521 (MPU6050) | 2 | 25 | ⚠️ 一个 AD0 改焊到 VCC |
| 4 | 减速电机 | N20 100RPM 6V 带编码器 | 2 | 50 | 确认带 AB 相霍尔编码器 |
| 5 | 电机驱动 | DRV8833 模块 | 1 | 20 | 红板小板，2A/路 |
| 6 | 舵机 | MG996R 金属齿轮 | 2 | 60 | 确认金属齿轮版本 |
| 7 | 轮子 | 43mm 橡胶轮 + N20 联轴器 | 2 | 20 | 联轴器要和 N20 D 型轴匹配 |
| 8 | 电池 | 3S 2200mAh 30C LiPo + XT60 插头 | 1 | 80 | 含充电器吗？确认 |
| 9 | 降压模块 | LM2596 (5V / **5A** 版本) | 1 | 15 | ⚠️ 要 5A 版，舵机峰值大 |
| 10 | LDO | AMS1117-3.3V 模块 | 1 | 3 | 供 IMU |
| 11 | 杜邦线 | 公母各 20 根 + 排针 | 1 套 | 10 | |
| 12 | 热缩管 | φ2/φ3/φ5 多规格 | 1 套 | 5 | |
| 13 | 电容 | 1000μF 16V 电解电容 | 2 | 4 | LM2596 输出端缓冲 |
| 14 | 开关 | 船型开关 / 拨动开关 | 1 | 2 | 总电源开关 |

| **合计** | | | | **~329** | |

### 8.2 结构件（3D 打印或手工）

| # | 部件 | 建议材料/方式 | 用量 |
|:-:|------|------|:---:|
| 1 | 车体底盘 | PLA 3D 打印 / 3mm 亚克力板切割 | 1 块 |
| 2 | 平台面板 | 3mm 亚克力 150×120mm | 1 块 |
| 3 | 云台万向节支架 | PLA 3D 打印 | 2 个（pitch + roll 轴） |
| 4 | 电机座 | PLA 3D 打印（固定 N20 到车架） | 2 个 |
| 5 | 电池座 | PLA 3D 打印（放置在车体底部） | 1 个 |
| 6 | IMU 减振垫片 | 橡胶/泡棉（IMU 和车体之间） | 2 片 |

> 如果没 3D 打印机，在 JLC 3D 打印服务下单，PLA 一套约 30-50 元。或者用亚克力板 + 热熔胶手搓。

### 8.3 工具

| # | 工具 | 必需？ | 备注 |
|:-:|------|:---:|------|
| 1 | 电烙铁 + 焊锡 | ✅ 必需 | 焊接排针、电机线 |
| 2 | 万用表 | ✅ 必需 | 查电压、短路 |
| 3 | USB-TTL 串口模块 | ✅ 必需 | 调试输出（STM32 的 USB 也可以模拟串口，备一个更灵活） |
| 4 | 螺丝刀套件 | ✅ 必需 | M2/M3 螺丝 |
| 5 | 热熔胶枪 | ⭕ 建议 | 固定小件、减振 |
| 6 | 3D 打印机 (或用打印服务) | ⭕ 建议 | 制作结构件 |
| 7 | 逻辑分析仪 (24MHz) | ⭕ 可选 | ~30 元，调 I2C/PWM 困住了再买 |
| 8 | 万用表 / 示波器 | ⭕ 可选 | 排查疑难硬件问题 |

---

## 9. 引脚分配

### 9.1 STM32F411CEU6 (BlackPill) 完整引脚分配

```
                    ┌────────────────────┐
                    │   STM32F411CEU6    │
                    │   (BlackPill)      │
                    │                    │
    车体IMU SDA ────┤ PB7  (I2C1_SDA)   │
    车体IMU SCL ────┤ PB6  (I2C1_SCL)   │
                    │                    │
    平台IMU SDA ────┤ PB3  (I2C2_SDA)   │  ← 或用 I2C1 但 AD0 设不同地址
    平台IMU SCL ────┤ PB10 (I2C2_SCL)   │
                    │                    │
    左轮PWM ────────┤ PA8  (TIM1_CH1)   │
    左轮IN2 ────────┤ PA9  (TIM1_CH2)   │  ← DRV8833 需 IN1/IN2 两路
    右轮PWM ────────┤ PA10 (TIM1_CH3)   │
    右轮IN2 ────────┤ PA11 (TIM1_CH4)   │
                    │                    │
    左轮编码器A ────┤ PA0  (TIM2_CH1)   │  ← 硬件编码器模式
    左轮编码器B ────┤ PA1  (TIM2_CH2)   │
    右轮编码器A ────┤ PA6  (TIM3_CH1)   │
    右轮编码器B ────┤ PA7  (TIM3_CH2)   │
                    │                    │
    舵机1 Pitch ────┤ PB8  (TIM4_CH3)   │
    舵机2 Roll  ────┤ PB9  (TIM4_CH4)   │
                    │                    │
    HC-05 TX ───────┤ PA3  (USART2_RX)  │
    HC-05 RX ───────┤ PA2  (USART2_TX)  │
                    │                    │
    调试 TX ────────┤ PA15 (USART1_TX)  │  ← 接 USB-TTL → 电脑
    调试 RX ────────┤ PA14 (USART1_RX)  │
                    │                    │
    状态 LED ───────┤ PC13 (板载LED)    │
    急停按键 ───────┤ PB12 (GPIO, 上拉) │  ← 可选：物理急停
                    └────────────────────┘
```

### 9.2 电源接线

```
LiPo 11.1V
    │
    ├──[船型开关]──┬── DRV8833 VM (电机电源 2.7-10.8V)
    │              │
    │              ├── LM2596 → 5V ──┬── STM32 5V pin
    │              │                 ├── HC-05 VCC (部分版本兼容 5V)
    │              │                 ├── 舵机 × 2 (V+)
    │              │                 │   └──[1000μF电容]── GND  ← 缓冲峰值电流
    │              │                 └── AMS1117 → 3.3V ──┬── MPU6050 × 2 VCC
    │              │                                     └── MPU6050 × 2 AD0
    │              │
    └──[BAT GND]───┴── 所有模块 GND 共地
```

> **重要**：舵机电源和逻辑电源 5V 可以共用，但 **GND 必须共地**。舵机的 5V 和 STM32 的 5V 从同一个 LM2596 出来，中间放个 1000μF 电解电容吸收舵机瞬态电流。

---

## 10. 安全机制

### 10.1 软件保护（固件内置）

```c
// 每个控制周期检查的安全条件
typedef enum {
    SAFE_OK = 0,
    SAFE_ANGLE_OVER,     // 车体倾角 > 45°
    SAFE_ENCODER_STALL,  // 编码器不转但 PWM 在输出（堵转）
    SAFE_BAT_LOW,        // 电池 < 3.3V/cell
    SAFE_ESTOP,          // 收到急停指令
} SafetyStatus;

SafetyStatus safety_check(void) {
    // 1. 倾角过大 → 瞬间关电机
    if (fabsf(car_angle) > 45.0f) {
        motor_stop();
        return SAFE_ANGLE_OVER;
    }
    
    // 2. 堵转检测：PWM > 50% 且 200ms 内无编码器变化
    if (abs(motor_pwm) > 128 && encoder_speed < 1.0f) {
        stall_timer += dt;
        if (stall_timer > 0.2f) {
            motor_stop();
            return SAFE_ENCODER_STALL;
        }
    } else {
        stall_timer = 0.0f;
    }
    
    // 3. 低电量：< 3.3V/cell → 降功率 → < 3.2V → 停止
    float cell_voltage = battery_voltage / 3.0f;
    if (cell_voltage < 3.2f) {
        motor_stop();
        return SAFE_BAT_LOW;
    } else if (cell_voltage < 3.4f) {
        // 限制最大 PWM 50%
        max_pwm = 128;
    }
    
    return SAFE_OK;
}
```

### 10.2 硬件保护

| 保护措施 | 实现方式 |
|---------|---------|
| 总电源开关 | 船型开关串联在 LiPo 正极 |
| 电机驱动过热 | DRV8833 内置过温关断（芯片级） |
| 舵机堵转 | MG996R 内置堵转保护（但别长时间堵） |
| 电池防过放 | LiPo 保护板（买电池时确认带保护板） |
| 急停 | 蓝牙指令 `E` + 可选物理按键 |

### 10.3 调试安全操作规范（你需要注意）

1. **任何时候第一次给电机供动力前**：小车用手扶着，确认"电机不会疯转"
2. **刷固件时**：小车平放不要立着
3. **第一次放手**：在柔软表面（地毯/床）上试，车倒了不会摔坏
4. **LiPo 电池**：不要过放（单节 <3.0V），不要刺穿，充电时人要在场

---

## 11. 风险与对策

| 风险 | 概率 | 严重度 | 对策 |
|------|:---:|:---:|------|
| PID 参数难调、车立不起来 | 中 | 高 | 仿真先行给初值；按 §4.5 口诀逐环调；多轮迭代 |
| 重心太高导致不平衡 | 中 | 高 | 电池放最底部；增加配重；降低平台安装高度 |
| 两级耦合振荡 | 中 | 中 | 频域解耦（50Hz vs 500Hz）；降低平台 Kp；前馈微调 |
| 舵机频繁动作发热/磨损 | 高 | 低 | PID 死区 ±2°；积分限幅；不连续、不微小、不急速调节 |
| 电机扭矩不够 | 低 | 中 | 整车重量控制 <1.5kg；不够换 N20 200RPM |
| 编码器信号丢失 | 低 | 高 | STM32 硬件编码器模式可靠性高；加 100nF 滤波电容 |
| 蓝牙断连车失控 | 低 | 中 | 断连 >2 秒自动停 + 急停指令/按键 |
| I2C 总线干扰 / IMU 数据异常 | 低 | 中 | 加 4.7kΩ 上拉电阻；校验 I2C 返回码；数据超范围检测 |
| 电池续航不足 | 低 | 低 | 已算过预算 OK；不够换 3000mAh |
| 3D 打印件强度不够 | 低 | 低 | 关键受力件加厚壁/填充；PLA 不够换 PETG |

---

## 附录 A：与原始方案的差异对照

| 项目 | 原始方案 | 修订方案 | 原因 |
|------|---------|---------|------|
| MCU | ESP32 | STM32F411CEU6 | 硬件编码器模式；用户偏好 |
| 平台执行器 | 舵机/无刷可选 | MG996R 舵机 | 用户选择方案 A |
| 通信 | 芯片内置 WiFi/BLE | HC-05 蓝牙 UART | STM32 无内置无线 |
| FOC 驱动器 | SimpleFOC Mini | 删除 | 不涉及无刷电机 |
| 遥控 | 未详述 | 手机蓝牙串口 App | 明确方案 |
| PID 实现 | 简化的伪代码 | 含抗饱和、微分滤波、死区 | 工程化 |
| 安全机制 | 缺失 | 倾角保护、堵转保护、低电保护、急停 | 安全必需 |
| 仿真 | 仅提及工具 | 详细 Python 仿真计划 | 减少实物试错 |
| 分工 | 抽象描述 | 每步标注 👤 / 🤖 / ↔ | 明确协作方式 |
| BOM 合计 | 500-800 元 | ~329 元（电子部分） | 简化方案自然降价 |
| 平台精度 | ±0.5°(宣称) | ±2°(实际) | MG996R 死区限制 |

---

## 附录 B：参考资源

| 资源 | 内容 | 链接 |
|------|------|------|
| STM32F4 HAL 库文档 | STM32CubeF4 HAL 驱动说明 | st.com |
| MPU6050 数据手册 | 寄存器映射、DMP 配置 | 网上搜索 "MPU-6000-6000C.pdf" |
| 平衡车 PID 原理 | 倒立摆控制详解 | howtomechatronics.com → search "balancing robot" |
| HC-05 AT 指令集 | 配置波特率/名称/主从模式 | 网上搜索 "HC-05 AT commands" |

---

> **下一步**：先确认这份修订方案没有问题，然后我从 Phase 1（Python 仿真代码）开始给你交付。
