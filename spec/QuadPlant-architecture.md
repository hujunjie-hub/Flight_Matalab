# QuadPlant 架构规格

状态：实现与验收分离；2026-11-09。物理保真度保持短时间局部刚体，执行方案统一为离散显式RK4。适用域见 QuadPlant-system.md。

## 1. 数值结构与执行边界

顶层 fixed-step discrete，500us，无 Continuous Integrator 或 continuous Model Reference。状态向量 x=[p(3),v(3),q(4),ω(3),motorω(4)] 共17维 double，Unit Delay 初值来自 Scenario。PlantStep 由四个可见的 PureRHS 数值子系统与 Sum/Gain 构成：k1=f(x,u)，k2=f(x+h*k1/2,u)，k3=f(x+h*k2/2,u)，k4=f(x+h*k3,u)，x_next=x+h*(k1+2*k2+2*k3+k4)/6。每个 RHS 重新计算姿态/力/接触，u 与外扰在间隔内保持。只在完整步后归一化 q，记录归一化前范数；中间阶段构造旋转矩阵用归一化工作副本，不反馈修改阶段状态。

| 组件 | 输入→输出 | 状态/DFT |
|---|---|---|
| AppliedFrameRegister | 到期 pending code→等效N目标 | 非DFT；初值stop，应用延迟500us |
| MotorRHS/RotorWrench | motorω/目标N→ω_dot/FRD wrench | 纯RHS，DFT；电机状态在17维寄存器 |
| Environment/GroundRHS | 本阶段x/外生场景→外力矩 | DFT；每RK4阶段重算接触 |
| RigidBodyRHS | 当前阶段x/wrench→p/v/q/ω导数 | DFT；不包含隐藏积分器 |
| RK4Step/PlantState | 四阶段RHS→x_next→x_k | Unit Delay非DFT，固定h=.0005s |
| SensorKinematics/Sampler | x_k及已应用命令→原始物理量/采样事件 | 数学DFT；队列/随机流非DFT |

Sample 相位在 PlantStep 之前，只读 x_k，不能输出 x_next 冒充同刻测量。SimStop 后 run_enable=false，x_next=x_k 并结束运行；冻结只实现终止语义，不是物理安全动作。离散日志先记 t_k，再保存 x_next，避免把未来状态标成当前时间。

## 2. 原点与动力学

N0 是绑定 Origin 的固定 ECEF 切平面 NED，C_0b 将 FRD 转 N0；Plant p/v/q/rate 都在这个固定局部框架。原点位于初始 CG，p0=[0,0,0]，地面 D=0.15m，CG→接地点 FRD=[0,0,.15]。WGS 锚点 45degN/0degE/100m 是初始 CG；Home 从 M4 捕获，不改变 Origin。Baro 基准在同一初始位置锁存，初始化 p_D=0/b_h=0 不会凭空产生0.15m创新。

对非重力外力 F_b，p_dot=v，v_dot=C_0b*F_b/m+g0；ω为 body 相对 N0 的 rate，ω_dot=J^-1*(τ-ω×Jω)，q_dot=.5*q⊗[0,ω]。固定局部刚体忽略地球自转对转动动量的微小影响；传感器前向模型仍与 KF 地理编排一致，不能把框架差异当 gyro bias 调掉。重力由 Flight Host SIL 共享参数提供；Earth rate 由 SIM_ONLY Origin 计算并转换到固定 N0。

GeodesyAdapter 严格区分点和向量：r_e=r0_e+C_e0*p0，v_e=C_e0*v0，R_0b=C_0e*C_en(LLH)*R_nb(KF)。位置经 ECEF 平移后旋转，速度/力只旋转；不能把 ecef2ned 位置函数用在速度上。LLH 当前 NED 的 transport 项留在 KF 内部；公开固定 N0 的 body rate 是 ω_b/N0，不是当前 LLH 导航系 rate。该语义纳入 G0 Nav rate 确认，不声称父 ICD 已明确。

## 3. 电机、载荷和接地

电机顺序、FRD 坐标、偏航符号、质量、惯量、推力上下限和一阶时间常数由同级 Flight/config/vehicle_model.yaml 提供。当前 Flight 合成配置的四个位置为 [0.18,-0.18,0]、[0.18,0.18,0]、[-0.18,0.18,0]、[-0.18,-0.18,0] m，偏航系数为 [-.02,+.02,-.02,+.02] m；这组参数没有硬件辨识证据。当前刚体内核只支持对角惯量，参数生成会拒绝非对角惯量，不能静默丢弃惯量积。

SIM_ONLY 专属参数包括转速到推力系数、空气阻力、转动阻尼和地面接触。ω_cmd=sqrt(max(f_cmd,0)/k_f)，motorω_dot=(ω_cmd-motorω)/tau，f_actual=k_f*motorω²。Plant 物理电机上限跟随 Flight vehicle config；当前 M7 DShot 虚拟量化曲线仍限制命令为0..10N。F_i=[0,0,-f_i]，τ_i=r_i×F_i+[0,0,gamma_i*f_i]。loss-of-effectiveness 是 Plant 内部物理故障，不把该真值直接写 M6/M7 能力 mask。

相对空气速度阻力 -Fdrag*v_air，转动阻尼 -Kω；所有外力先注明 frame 再变换。PlantParameters 固定19项：p[0]=mass，p[1..3]=diag(J)，p[4]=kf，p[5]=motor tau，p[6..8]=NED drag，p[9]=rate damping，p[10..12]=ground stiffness/damping/down，p[13..15]=contact lever FRD，p[16]=gravity，p[17..18]=skid half-span。参数由 generate_parameters 统一生成；任何维度或物理范围不匹配都应在模型运行前失败。M7 输入 N 来自量化 code 逆映射，无第二次 PWM 解释。电机ω/实际力只到传感器和只读评价，ESC反馈 NONE。

接触必须先按几何门控：p_contact_D<ground_D 时 Fn=0，与下降速度无关；否则 δ=p_contact_D-ground_D，Fn=max(0,k*δ+c*v_contact_D)，向 N0 Up 作用并产生 CG 力矩。接地之外不得有阻尼悬浮力；离地后不粘地，不用状态投影/瞬移纠正穿透。第一版明确不建水平地面摩擦；超2cm基准穿透或非有限即 FAIL。

GroundContact fixture 用有符号间隙 gap=ground_D-p_contact_D 判定：gap≤1mm 且穿透 δ≤2cm、测量有效时给 CONTACT；合法静态压缩不会因 abs(gap)>1mm 丢失接地，sample 每500us、TTL1000us；无随机误判为名义假设，drop/stuck 在独立故障场景注入。M4 仍需 Nav 加速度/速度和2s dwell，不能只凭该位宣布 LANDED。

## 4. 传感器与 M2 入口

设 l_I 为 CG→IMU，v_I=v_CG+C*(ω×l_I)，a_I=a_CG+C*(α×l_I+ω×(ω×l_I))，其中 ω=ω_b/N0、α为同刻局部角加速度。原始 gyro=ω+C'*ω_ie^0，比力 f_I=C'*(a_I-g0+2*ω_ie^0×v_I)。当前 SIM sensor adapter 已加入固定 N0 Earth-rate 和 Coriolis 项，使用 Plant 初始速度初始化差分器，并屏蔽首个无差分 IMU 样本；非零 IMU 杆臂、安装矩阵、bias、随机噪声、采样队列和 transport delay 仍待 P3 完成。

GNSS 点按天线 LLH/速度合成，Mag N0 场[25,0,40]uT；Baro 以合成压力高度基准100m和 Up 位移生成，再用 M2 同一压力转换函数的逆生成 pressure。该100m压力基准是明确合成假设，不把椭球高等同实测压力高度；h_baro0 由 M3 锁存。

UM982/PPS 为固定主要器件，不建“可选GNSS”名义 Variant。GNSS PVT、PPS边沿、时间历元分别走 SIM_PVT/SIM_PPS_EPOCH 适配；PVT失锁不伪造新数据或清配置，PPS是否仍可靠由该故障场景明确给证据。真实 RAW_CAPTURE 中的 UM982 串口解码仍需正式后端；不能把合成 PVT 通过当成已验收原生解析器。

SensorFrontend 默认 SIM_RAW_ENGINEERING 子格式：生成 sensor 轴系工程量/捕获时间/质量，私有虚拟采集适配进入 M2 校准/安装/时间处理，M2 出口才是公共标准样本。该模式验证处理数学，不验证 ADIS 二进制解码或驱动。RAW_CAPTURE 另用于真实字节解码 fixture。M2_STANDARD 回放则只验证转发，禁止再做校准或扣 pipeline；input_level/subformat 必须写 manifest。

| 源 | 采样率/STD | sample→capture→arrival |
|---|---|---|
| IMU | 1kHz，gyro.001rad/s、accel.02m/s² | capture=sample+2000us，arrival=capture+300us |
| GNSS | 10Hz，pos.2m/axis、vel.03m/s/axis | 合成有效sample，arrival=sample+10000us |
| PPS / GNSS历元 | 1Hz固定启用，独立捕获质量/历元有效位 | raw tick锁存；PPS arrival=capture+100us，历元arrival=对应秒+10000us；UTC不在8个有效间隔之前假锁定 |
| Baro | 100Hz，高度.05m | arrival=sample+5000us |
| Mag | 100Hz，.1uT/axis | arrival=sample+3000us |
| GroundContact | 2kHz，名义无随机误判 | arrival=sample，TTL1000us |

IMU 原始捕获时刻在 M2 减已知2000us一次；STANDARD 消息直接携带校正 sample 并标 PIPELINE_CORRECTED，不再扣一次。随机流以 seed/source/measurement sequence 派生，不能依赖 RK4 调用次数；步长细化不改变输入噪声序列。参数 STD/PSD 分开记录；纯数值与噪声统计分别验收。

## 5. 数值证据和限制

P-12 在同一500us外层调用内比较一次500us RK4与两个250us RK4子步，保持 Frame 应用延迟、sensor采样/arrival、输入保持和随机序列完全相同，只改变物理积分精度。子步内不再触发 Chart/队列/噪声。连续块或 Aerospace 6DOF 不能直接混入活动方案；若以后整体换积分策略，需重验执行时序/符号/收敛再替换本方案。

Truth 只有 SensorFrontend 和只读 Evaluator 可动态读取；初始化来自同一 Scenario 先验配置而非运行中 truth 反馈。没有 HIL 实时性或飞行安全放行结论。
