# QuadPlant 系统规格

状态：SIM_ONLY 物理模型；2026-11-09。属于 FlightSIM 的 MIL 物理侧，仅由 FMT_MILSIM 激活。

## 1. 用途和证据边界

为 MPC / SO(3) / Rate PID / 控制分配 / FMS 提供可重复的四旋翼软件闭环。Plant 采用固定质量六自由度刚体、四电机一阶转速、线性空气阻力、几何门控地面接触和可控外部扰动。

本模型中的 Flight 车辆配置仍标记为 SIM_ONLY 合成配置，不代表实机辨识结果。当前没有实物推力台架、惯量测量、风场测试或 ESC 动态测试数据。真实参数接入前必须记录来源、单位、标定条件、误差和版本；不得把仿真通过解释为实机精度或飞行放行。

## 2. 输入、输出和坐标约定

| 类别 | 输入/输出 | 单位/基准 |
|---|---|---|
| u 命令 | 经执行器帧应用后的四路目标推力 | N，电机顺序沿用 Flight |
| w 扰动 | 风、外力、外力矩、地面开关、电机效能 | m/s、N、N·m、无量纲 |
| y 测量 | IMU、GNSS/PPS、Baro、Mag、GroundContact | 标准样本、独立授时事件和物理采样时刻 |
| z 真值 | CG 位置/速度/姿态/角速度、电机转速/推力、接触力 | double，只供传感器合成和只读评价 |

PlantState 为 17 维 double：

[p_NED(3), v_NED(3), q_0b(wxyz)(4), omega_b/N0(3), motor_omega(4)]

- N0：绑定初始 Origin 的固定局部 NED。
- FRD：机体前-右-下坐标系。
- C_0b：FRD 向量转换到固定 N0 的方向余弦矩阵，按行存储。
- 四元数：scalar-first [w,x,y,z]，表示 body 到 N0 的姿态。
- omega_b/N0：机体相对固定 N0 的角速度，表达在 FRD；不是当前地理 NED 导航系角速度。

Environment 固定为 15 个 double，字段顺序不能私自调整：

| MATLAB 下标 | 字段 | 单位/坐标 |
|---|---|---|
| 1:3 | wind_NED | m/s，固定 NED 风速 |
| 4:6 | external_force_NED | N，固定 NED 外力 |
| 7:9 | external_torque_FRD | N·m，机体 FRD 外力矩 |
| 10 | ground_enable | 0 或 1 |
| 11 | drag_enable | 0 或 1 |
| 12:15 | rotor_effectiveness | 每个电机 [0,1] |

RotorWrench 和 GroundWrench 均为 FRD 机体系六维力/力矩。刚体模型只在合力计算时将机体系力旋转到固定 NED；Environment 中的外力已是 NED，不得再次旋转。Environment 外力矩明确为 FRD，不得当作 NED 力矩直接相加。

Command → Motor → RotorWrench → RigidBody → SensorSimulation 的物理因果链必须闭合。PlantTruth 不得直接进入 Estimator、FMS 或 Controller；仅允许初始化、传感器合成和只读 Evaluator 访问真值。

## 3. 范围和 SIM_ONLY 工作点

局部仿真范围为 Origin 附近约 8 m，名义倾角不超过 25°、速度不超过 2 m/s、角速度不超过 [2,2,1] rad/s。Origin 绑定初始 CG，局部位置初值为零，地面 D=0.15 m；WGS 锚点为合成 45°N/0°E/100 m 椭球高，不代表真实起飞点或 AMSL。

| 参数 | 当前参数视图 | 来源/性质 |
|---|---|---|
| 质量 m | 1.5 kg | Flight/config/vehicle_model.yaml，仍为 SIM_ONLY |
| 转动惯量 J | diag[0.025, 0.025, 0.04] kg·m² | Flight 合成配置；当前内核只支持对角惯量 |
| 电机位置 | (+0.18,-0.18)、(+0.18,+0.18)、(-0.18,+0.18)、(-0.18,-0.18) m | Flight 合成配置，FRD |
| 径向力臂 | 0.254558 m | 从电机坐标推导，不独立手填 |
| 偏航力矩系数 | [-0.02,+0.02,-0.02,+0.02] m | Flight 合成配置，带符号 |
| 电机推力限制 | 0～15 N/电机 | Flight 合成配置 |
| 电机推力系数 k_f | 1e-5 N/(rad/s)² | SIM_ONLY 合成参数 |
| 电机时间常数 | 0.03 s | Flight 合成配置，四电机当前相同 |
| 线性阻力 | [0.1,0.1,0.15] kg/s | SIM_ONLY 合成参数 |
| 角速度阻尼 | 0.002 N·m·s/rad | SIM_ONLY 合成参数 |
| 地面刚度/阻尼 | 5000 N/m / 100 N·s/m | SIM_ONLY 接触近似，不是实测起落架 |
| 地面 D | 0.15 m | 固定局部 NED 场景参数 |

注意区分两个不同的限制：Plant 的物理电机推力上限来自 Flight 车辆配置，为 15 N；当前独立 M7/DShot 帧量化夹具的力曲线为 0～10 N。后者不是 Plant 的物理推力上限，二者不可共用同一个参数字段。

Plant 初始状态 p_D=0、接地点杆臂 D=0.15 m、地面 D=0.15 m，代表无预压缩的几何接触初值。开启地面接触后会出现短暂悬架压缩/稳定过程；它不是静态受力平衡初值。静态支撑验收另使用 delta=mg/k 的压缩量，当前约 2.94 mm。

## 4. 动力学和接触

电机模型：

omega_cmd = sqrt(clamp(f_cmd, f_min, f_max) / k_f)

omega_dot = (omega_cmd - omega) / tau

f_actual = k_f * omega^2 * rotor_effectiveness

转子力沿 body -Z 方向。力矩由 r_i × F_i 和带符号偏航反扭矩系数构成。电机编号和几何矩阵从 Flight 配置生成；不允许在 MATLAB 中另写一套电机顺序。

刚体模型：

p_dot = v_NED

v_dot = C_0b * F_body / m + F_external_NED / m + [0,0,g]

omega_dot = J^-1 * (tau_body + tau_external_FRD - omega × J*omega - D*omega)

q_dot = 0.5 * q ⊗ [0, omega_b/N0]

当前刚体内核使用对角惯量。参数生成时会拒绝非对角惯量，避免静默丢弃惯性耦合项。若未来 Flight 引入非对角惯量，必须扩展完整矩阵动力学和测试，不能仅修改 YAML。

空气阻力为 -D_v * (v_NED - wind_NED)，仅在 drag_enable=1 时生效。

地面接触按四个接触点逐点计算。只有接触点进入地面后才产生弹簧/阻尼力；离地时严格为零。法向力向 NED Up 方向作用，并通过接触杆臂产生 CG 力矩。水平摩擦采用正则化 Coulomb 近似。模型不做状态瞬移或穿透投影修正；基准落体穿透超过 2 cm 或出现 NaN/Inf 即失败。

## 5. 验收和限制

先做组件开环，再做 Plant 物理开环，最后才允许进入系统闭环。当前代码覆盖电机、载荷、自由落体、悬停、姿态符号、RK4 步长收敛、损失效能、接触、坐标变换、风阻和输入拒绝。传感器杆臂、Earth 项、噪声统计、采样延迟和真值隔离仍需独立验收。

目标是功能 MIL，不要求实时运行。Host 运行快慢不能推断 H723 实时性。当前 Plant 采用 double 精度和固定步长显式 RK4；固件公开接口的 single 转换、传感器延迟和执行器帧应用延迟属于系统闭环边界，不可用理想状态反馈掩盖。
