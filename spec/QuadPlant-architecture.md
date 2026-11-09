# QuadPlant 架构规格

状态：SIM_ONLY 物理模型实现与验证阶段；2026-11-09。执行方案为离散显式 RK4，适用域见 QuadPlant 系统规格。

## 1. 数值结构与执行边界

顶层 fixed-step discrete，基步 500 μs，无 Continuous Integrator 或 continuous Model Reference。状态向量：

x=[p_NED(3),v_NED(3),q_0b(wxyz)(4),omega_b/N0(3),motor_omega(4)]

共 17 维 double。Unit Delay 初值来自 Scenario。PlantStep 由四个 PureRHS 阶段构成：

k1=f(x,u)
k2=f(x+h*k1/2,u)
k3=f(x+h*k2/2,u)
k4=f(x+h*k3,u)
x_next=x+h*(k1+2*k2+2*k3+k4)/6

每个 RHS 重新计算姿态、旋翼力、阻力和接触力；一个物理步内 u 与外扰保持不变。只在完整步后归一化 q，记录归一化前范数；中间阶段构造旋转矩阵时只归一化工作副本，不修改阶段状态。

| 组件 | 输入 → 输出 | 状态/执行约束 |
|---|---|---|
| MotorRHS | motor_omega/target_force → omega_dot/actual_force | 一阶转速模型，物理推力限幅 |
| RotorWrench | 四路 actual_force → FRD wrench | 共享 Flight 电机几何与偏航符号 |
| GroundRHS | PlantState/Environment → FRD wrench/gap/normal | 每个 RK4 阶段重算接触 |
| RigidBodyRHS | 当前 x/wrench/Environment → p/v/q/omega 导数 | 六自由度刚体，无隐藏积分器 |
| RK4Step | 四阶段 RHS → x_next | 固定物理步长，步后归一化 q |
| SensorSimulation | x_k → 物理测量/采样事件 | 后续阶段实现，真值不得直达控制器 |

Sample 相位在 PlantStep 之前，只读 x_k，不能输出 x_next 冒充同刻测量。仿真停止时冻结状态只实现终止语义，不代表物理安全动作。日志先记录 t_k，再保存 x_next，避免把未来状态标成当前时间。

## 2. 原点、姿态和动力学

N0 是绑定 Origin 的固定局部 NED，C_0b 将 FRD 转到 N0；Plant 的 p/v/q/rate 都在固定局部框架。Origin 位于初始 CG，p0=[0,0,0]，地面 D=0.15 m，CG→接地点 FRD=[0,0,0.15] m。WGS 锚点为明确合成 45°N/0°E/100 m 椭球高。Home 从 M4 捕获，不改变 Origin。

omega 表示 body 相对固定 N0 的角速度，并表达在 FRD。刚体方程使用完整 J*omega 和 omega × J*omega；J 必须是对称正定 3×3 矩阵，角加速度由完整矩阵求解，不能只使用对角项。

位置是点，速度/力是向量：位置需要 ECEF 平移后转换，速度/力只旋转。当前地理 NED 的 transport 项留在 KF 内部；Plant 的固定 N0 角速度定义不能和当前地理导航系角速度混用。

## 3. Environment 和电机/接触约定

Environment 是固定 15 维 double：

| 下标 | 字段 | 单位/坐标 |
|---|---|---|
| 1:3 | wind_NED | m/s，固定 NED |
| 4:6 | external_force_NED | N，固定 NED |
| 7:9 | external_torque_FRD | N·m，机体 FRD |
| 10 | ground_enable | 0/1 |
| 11 | drag_enable | 0/1 |
| 12:15 | rotor_effectiveness | 每个电机 0..1 |

Environment 中任何非有限值、非法布尔值或超界电机效能都必须 fail closed。PlantState 17 个元素必须有限，四元数不能为零，电机转速不能为负。Plant 参数向量固定 26 个 double：`[mass; J(:); k_f; tau; drag(3); rateDamping; groundK; groundC; groundDown; contactLever(3); gravity; skidHalfSpan(2); friction]`。质量、惯量正定性、电机推力系数、电机时间常数、重力和地面刚度必须满足物理约束；阻尼、摩擦和半跨距不能为负。

电机顺序沿用 Flight：前左、前右、后右、后左。当前位置分别为 (+0.18,-0.18)、(+0.18,+0.18)、(-0.18,+0.18)、(-0.18,-0.18) m。径向力臂由坐标推导为 0.254558 m；偏航系数为 [-0.02,+0.02,-0.02,+0.02] m。

omega_cmd=sqrt(clamp(f_cmd,f_min,f_max)/k_f)
motor_omega_dot=(omega_cmd-motor_omega)/tau
f_actual=k_f*motor_omega^2

Plant 物理最大推力为 15 N/电机，电机时间常数为 0.03 s；这些是 Flight 当前 SIM_ONLY 配置，不是硬件测量。M7/DShot 独立帧量化夹具仍使用 0～10 N 力曲线，必须与 Plant 最大推力分开维护。

F_i=[0,0,-f_i]，tau_i=r_i×F_i+[0,0,gamma_i*f_i]。电机效能退化只改变实际推力，不直接改写 M6/M7 能力位。RotorWrench 和 GroundWrench 均在 FRD 表达；外力 NED 与外力矩 FRD 的坐标定义必须保持显式。

接触几何门控：接触点在地面上方时 Fn=0，与下降速度无关；进入地面后 delta=contact_down-ground_down，Fn=max(0,k*delta+c*v_contact_down)，力沿 NED Up 作用并产生 CG 力矩。离地后不保留接触力，不使用状态投影/瞬移纠正穿透。水平摩擦为正则化 Coulomb 近似。

## 4. 传感器和后续边界

传感器运动学需要考虑 CG→IMU 杆臂：

v_I=v_CG+C*(omega×l_I)

a_I=a_CG+C*(alpha×l_I+omega×(omega×l_I))

gyro、specific force、GNSS 天线运动、Mag、Baro、PPS 和 GroundContact 的采样时刻、捕获时刻、到达时刻及延迟应分别记录。噪声随机流必须由 seed/source/measurement sequence 派生，不能依赖 RK4 调用次数；步长细化不得改变噪声序列。

这些传感器能力属于后续 P3，不因当前刚体 Plant 通过而自动验收。

## 5. 数值证据和限制

P-12 使用相同初始状态、输入保持和环境，对比 Simulink 500 μs RK4 输出与独立 250 μs RK4 参考轨迹；只比较平滑无接触场景的位置和姿态误差。完整系统闭环中的传感器采样、队列、随机流和固定 500 μs 执行器帧应用时序仍需单独验证。

Truth 只允许 SensorSimulation、初始化和只读 Evaluator 访问，不能直接连入 Nav/Control。没有 HIL 实时性或飞行安全放行结论。
