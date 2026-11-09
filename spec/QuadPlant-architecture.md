# QuadPlant 架构规格

状态：设计草案；2026-11-05。物理保真度保持短时间局部刚体，执行方案统一为离散显式RK4。适用域见[Plant系统](QuadPlant-system.md)。

## 1. 数值结构与执行边界

顶层fixed-step discrete，500us，无Continuous Integrator或continuous Model Reference。状态向量x=[p(3),v(3),q(4),ω(3),motorω(4)]共17维double，Unit Delay初值来自Scenario。PlantStep由四个可见的PureRHS数值子系统与Sum/Gain构成：k1=f(x,u)，k2=f(x+h*k1/2,u)，k3=f(x+h*k2/2,u)，k4=f(x+h*k3,u)，x_next=x+h*(k1+2*k2+2*k3+k4)/6。每个RHS重新计算姿态/力/接触，u与外扰在间隔内保持。只在完整步后归一化q，记录归一化前范数；中间阶段构造旋转矩阵用归一化工作副本，不反馈修改阶段状态。

| 组件 | 输入→输出 | 状态/DFT |
|---|---|---|
| AppliedFrameRegister | 到期pending code→等效N目标 | 非DFT；初值stop，应用延迟500us |
| MotorRHS/RotorWrench | motorω/目标N→ω_dot/FRD wrench | 纯RHS，DFT；电机状态在17维寄存器 |
| Environment/GroundRHS | 本阶段状态/外生场景→外力矩 | DFT；每RK4阶段重算接触 |
| RigidBodyRHS | 当前阶段x/wrench→p/v/q/ω导数 | DFT；不包含隐藏积分器 |
| RK4Step/PlantState | 四阶段RHS→x_next→x_k | Unit Delay非DFT，固定h=.0005s |
| SensorKinematics/Sampler | x_k及已应用命令→原始物理量/采样事件 | 数学DFT；队列/随机流非DFT |

Sample相位在PlantStep之前，只读x_k，不能输出x_next冒充同刻测量。SimStop后run_enable=false，x_next=x_k并结束运行；冻结只实现终止语义，不是物理安全动作。离散日志先记t_k，再保存x_next，避免把未来状态标成当前时间。

## 2. 原点与动力学

N0是绑定Origin的固定ECEF切平面NED，C_0b将FRD转N0；Plant p/v/q/rate都在这个固定局部框架。原点位于初始CG，p0=[0,0,0]，地面D=0.15m，CG→接地点FRD=[0,0,.15]。WGS锚点45degN/0degE/100m是初始CG；Home从M4捕获，不改变Origin。Baro基准在同一初始位置锁存，初始化p_D=0/b_h=0不会凭空产生0.15m创新。

对非重力外力F_b，p_dot=v，v_dot=C_0b*F_b/m+g0；ω为body相对N0的rate，ω_dot=J^-1*(τ-ω×Jω)，q_dot=.5*q⊗[0,ω]。固定局部刚体忽略地球自转对转动动量的微小影响；传感器前向模型仍与KF地理编排一致，不能把框架差异当gyro bias调掉。重力g0由共享WGS函数在锚点生成，短域内常量近似入manifest。

GeodesyAdapter严格区分点和向量：r_e=r0_e+C_e0*p0，v_e=C_e0*v0，R_0b=C_0e*C_en(LLH)*R_nb(KF)。位置经ECEF平移后旋转，速度/力只旋转；不能把ecef2ned位置函数用在速度上。LLH当前NED的transport项留在KF内部；公开固定N0的body rate是ω_b/N0，不是当前LLH导航系rate。该语义纳入G0 Nav rate确认，不声称父ICD已明确。

## 3. 电机、载荷和接地

ω_cmd=sqrt(max(f_cmd,0)/k_f)，motorω_dot=(ω_cmd-motorω)/tau，f_actual=k_f*motorω²；0..10N目标，对应0..1000rad/s。四电机顺序前左/前右/后右/后左，位置分别(+a,-a),(+a,+a),(-a,+a),(-a,-a)，a=.225/sqrt(2)m；F_i=[0,0,-f_i]，τ_i=r_i×F_i+[0,0,gamma_i*f_i]。loss-of-effectiveness是Plant内部物理故障，不把该真值直接写M6/M7能力mask。

相对空气速度阻力-Fdrag*v_air，转动阻尼-Kω；所有外力先注明frame再变换。M7输入N来自量化code逆映射，无第二次PWM解释。电机ω/实际力只到传感器和只读评价，ESC反馈NONE。

接触必须先按几何门控：p_contact_D<ground_D时Fn=0，与下降速度无关；否则δ=p_contact_D-ground_D，Fn=max(0,k*δ+c*v_contact_D)，向N0 Up作用并产生CG力矩。接地之外不得有阻尼悬浮力；离地后不粘地，不用状态投影/瞬移纠正穿透。无水平摩擦，超2cm基准穿透或非有限即FAIL。

GroundContact fixture用有符号间隙gap=ground_D-p_contact_D判定：gap≤1mm且穿透δ≤2cm、测量有效时给CONTACT；合法静态压缩不会因abs(gap)>1mm丢失接地，sample每500us、TTL1000us；无随机误判为名义假设，drop/stuck在独立故障场景注入。M4仍需Nav加速度/速度和2s dwell，不能只凭该位宣布LANDED。

## 4. 传感器与M2入口

设l_I为CG→IMU，v_I=v_CG+C*(ω×l_I)，a_I=a_CG+C*(α×l_I+ω×(ω×l_I))，其中ω=ω_b/N0、α为同刻局部角加速度。原始gyro=ω+C'*ω_ie^0，比力f_I=C'*(a_I-g0+2*ω_ie^0×v_I)。Origin固定于ECEF，不能在此再加当前地理NED的transport项；KF在其内部当前LLH/NED编排使用wie+wen，适配器负责基变换。

GNSS点按天线LLH/速度合成，Mag N0场[25,0,40]uT；Baro以合成压力高度基准100m和Up位移生成，再用M2同一压力转换函数的逆生成pressure。该100m压力基准是明确合成假设，不把椭球高等同实测压力高度；h_baro0由M3锁存。

UM982/PPS为固定主要器件，不建“可选GNSS”名义Variant。GNSS PVT、PPS边沿、时间历元分别走SIM_PVT/SIM_PPS_EPOCH适配；PVT失锁不伪造新数据或清配置，PPS是否仍可靠由该故障场景明确给证据。PPS不是刚体状态的函数，其捕获raw tick/历元关联/理想时基边界见执行协议第8节。真实RAW_CAPTURE中的UM982串口解码仍需正式后端；不能把合成PVT通过当成已验收原生解析器。

SensorFrontend默认SIM_RAW_ENGINEERING子格式：生成sensor轴系工程量/捕获时间/质量，私有虚拟采集适配进入M2校准/安装/时间处理，M2出口才是公共标准样本。该模式验证处理数学，不验证ADIS二进制解码或驱动。RAW_CAPTURE另用于真实字节解码fixture。M2_STANDARD回放则只验证转发，禁止再做校准或扣pipeline；input_level/subformat必须写manifest。

| 源 | 采样率/STD | sample→capture→arrival |
|---|---|---|
| IMU | 1kHz，gyro.001rad/s、accel.02m/s² | capture=sample+2000us，arrival=capture+300us |
| GNSS | 10Hz，pos.2m/axis、vel.03m/s/axis | 合成有效sample，arrival=sample+10000us |
| PPS / GNSS历元 | 1Hz固定启用，独立捕获质量/历元有效位 | raw tick锁存；PPS arrival=capture+100us，历元arrival=对应秒+10000us；UTC不在8个有效间隔之前假锁定 |
| Baro | 100Hz，高度.05m | arrival=sample+5000us，压力参考明确 |
| Mag | 100Hz，.1uT/axis | arrival=sample+3000us |
| GroundContact | 2kHz，名义无随机误判 | arrival=sample，TTL1000us |

IMU原始捕获时刻在M2减已知2000us一次；STANDARD消息直接携带校正sample并标PIPELINE_CORRECTED，不再扣一次。first arrival2300us在2500us释放，额外200us为调度等待，不是测量误差。轴间时延测试按物理历史生成，先因果对齐共同旧sample。

随机流以seed/source/measurement sequence派生，不能依赖RK4调用次数；步长细化不改变输入噪声序列。参数STD/PSD分开记录；纯数值与噪声统计分别验收。

## 5. 数值证据和限制

P-12在同一500us外层调用内比较一次500us RK4与两个250us RK4子步，保持Frame应用延迟、sensor采样/arrival、输入保持和随机序列完全相同，只改变物理积分精度。子步内不再触发Chart/队列/噪声。连续块或Aerospace 6DOF不能直接混入活动方案；若以后整体换积分策略，需重验执行时序/符号/收敛再替换本方案。

Truth只有SensorFrontend和只读Evaluator可动态读取；初始化来自同一Scenario先验配置而非运行中truth反馈。没有HIL实时性或飞行安全放行结论。
