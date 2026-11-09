# QuadPlant 验证计划

状态：测试脚本持续补充；MATLAB 执行状态以每次生成的 validation report 为准。2026-11-09。

## 1. 分级验收

先组件开环，再集成物理开环，最后 MIL 闭环。每个结果同时记参数/模型/场景 Hash、求解器、步长、frame 及精度。以下阈值是 SIM 数学接纳值，不是实物精度承诺。

| ID | 试验 | 验收/依据 |
|---|---|---|
| P-01 | 0→5N电机目标阶跃，1s | 单调/有限，ω在5tau后距目标<1%；推力按k_f*ω² |
| P-02 | 四路相等推力 | τx/y/z残差≤1e-10Nm（double），Fz=-sum f |
| P-03 | 单路电机 | τx=-y、τy=x、τz=gamma，与 Flight motor position/yaw ratio 的 FRD 力矩矩阵一致 |
| P-04 | 无推力/无drag自由落体0.1s，无地面 | Δv_D=g*t，Δp_D=.5g*t²，误差≤1e-6m/1e-6m/s |
| P-05 | 恒定mg向上合力，无扰动2s | v漂移≤1e-6m/s；不得重复加gravity |
| P-06 | q/-q与非零yaw初值 | 同一C_nb/物理轨迹；q范数误差≤1e-6 |
| P-07 | 非零 IMU/天线杆臂旋转 | IMU 向心/切向加速度及 GNSS 天线位置/速度符合刚体解析式，误差≤1e-6（double理想层） |
| P-08 | 静止水平IMU | specific force=[0,0,-g]，gyro含固定 N0 Earth-rate 项；不把固定 N0 相对 rate=0 当 gyro 全0 |
| P-09 | 噪声 seed 重复/独立源 | 同 seed 序列相同；统计 STD 在长样本95%置信检查范围 |
| P-10 | 多速率事件时序与 GNSS 时间基准 | P-10a 已实现 IMU/GNSS/MAG/Baro sample/capture/arrival/release 队列；P-10b 复用 Flight TimeService 与 GNSS outage 上游 host tests，验证 PPS 频率驯服、UTC/PPS 配对、UTC mapping、PVT/UTC/PPS 独立失效、holdover 和重捕获；Host MIL 的 TIM2 capture/UM982 RECTIME 注入链仍未接入 |
| P-11 | 地面落体/起飞 | 非负 Fn、无 NaN/Inf，最大穿透<2cm（基准场景），离地后不保持接触力 |
| P-12 | 积分步长收敛 | 5s悬停/偏航无接触场景，相同初始状态和四路推力保持下，500us Simulink RK4 与独立250us RK4参考比较：位置差<1e-3m、姿态差<1e-4rad；只验证Plant积分精度，不代表系统级时序验收 |
| P-13 | loss-of-effectiveness/外力 | 真值改变经测量反映，不能直接给 M4“传感器坏”的标签 |
| P-14 | truth 隔离 | 图依赖检查：无 truth→Nav/Control 捷径；只有 SensorSimulation、初始化和 Evaluator 例外 |
| P-15 | 几何尚未接触但快速下降 | 距地1cm、v_D=1m/s时 Fn 严格0；禁止接地之外的阻尼悬浮 |
| P-16 | 静态接触平衡 | 四角接触弹簧压缩约 mg/k；有符号 gap 为负仍有效，法向力约 mg，力矩近零 |
| P-17 | 水平接触运动 | 第一版无水平地面摩擦，水平速度不产生水平接触力或额外力矩 |
| P-18 | 惯量参数与坐标合同 | 完整3×3惯量必须对称正定且参数生成保留全部九个元素；FRD机体系力转固定NED、外部FRD力矩按完整惯量求角加速度 |
| P-19 | 风阻 | 阻力使用 v_NED-wind_NED，而不是地速本身 |
| P-20 | 非对角惯量动力学 | J·ω、ω×(J·ω) 和 J⁻¹角加速度均使用完整矩阵 |
| P-21 | 输入拒绝 | NaN/Inf、非法开关、超界 rotor_effectiveness、非对称或非正定 J 必须 fail closed |

P-12 不满足须整体重选积分细化/接触参数并更新方案，不能放宽阈值；改变物理步长时保持外层时序，避免把延迟变化当收敛。P-09统计窗口可用10s以上，StopTime必须有限。

P-10a 事件队列由 `verify_sensor_event_timing` 检查固定 GNSS PVT、IMU/MAG/Baro 多速率 sample/capture/arrival；500 μs 队列 release 不能替代物理 capture。generated/suppressed/released/accepted 计数满足 opportunities=generated+suppressed、generated=released+pending、released=accepted；抑制样本后下一有效事件必须出现序号缺口。P-10b 由两个独立 gate 覆盖：`verify_time_service_sync` 编译同级 Flight 的真实 `sensor_device/time_base/systime.c` 并运行上游 `tests/time/test_time_service.c`，覆盖 PPS period gate/频率锁定/holdover、UTC observation 与 PPS 配对、UTC mapping 不确定度、外部时钟映射和 time_epoch 变化拒绝；`verify_gnss_time_recovery` 编译真实 TimeService 与 GNSS sample normalization/filter/calibration，并运行 `tests/drivers/test_gnss_outage.c`，覆盖有效 PVT/无 Fix、旧 PVT 拒绝、PVT loss 与 PPS/UTC health 解耦、UTC loss、PPS loss、holdover、重捕获和坏边沿拒绝。两者 PPS 输入均为合成 `PpsCaptureEvent`，不等同真实 TIM2 ISR；当前 Host SIL `sil_flight.c` 仍将 time service API stub 为 `STATUS_NOT_READY`，UM982 UART RECTIME 未进入 MIL。因此 P-10b 的算法与 GNSS 失效恢复有独立回归，端到端 Host MIL PPS/RECTIME 链仍未实现，P-10 整体不能标为 PASS。

P-04/05/07/08 理想层关闭噪声、地面或电机动态的具体旁路必须在 fixture 记录；生产闭环不得继承这些测试旁路。P-11 基准为地面上方0.1m、零初速、无推力落体；另设高落差场景，不能把2cm门限外推到任意撞击。P-09采用10000个独立白噪声样本，按卡方双侧95%区间检验各轴方差；固定 seed 用于回归，未通过不得反复挑 seed。q差使用 atan2 度量。

## 2. 当前脚本覆盖

verify_plant_open_loop 当前代码覆盖 P-01..P-09、P-10a、P-11..P-13、P-15..P-21；P-09 已实现同 seed 可复现、不同 seed 变化、IMU 白噪声 STD 的 95% 卡方区间、轴间独立性及 bias/scale 注入。P-10a 队列子项由 `verify_sensor_event_timing` 独立检查多速率周期、sample/capture/arrival/release、队列释放迟到、计数守恒、缺测序号缺口、非法时间步/掩码和 freshness 边界，并由 `verify_plant_open_loop` 调用；P-10b TimeService 与 GNSS outage 核心分别由 `verify_time_service_sync`、`verify_gnss_time_recovery` 编译真实 Flight 源并运行上游测试，且均纳入 `run_component_checks`；但物理 PPS capture ISR、UM982 RECTIME→PPS 配对和 Host MIL 时间域映射链尚未接通，故 P-10 整体仍为 PARTIAL。P-14 truth 依赖图检查由 `verify_truth_isolation` 独立实现，并由 `run_component_checks` 调用。Plant 报告必须为 PARTIAL，且必须在 MATLAB/Simulink 环境实际执行；静态代码审查不算测试通过。

## 3. 系统闭环评价

只在 P-01..P-21 适用项通过且共享 FCS 合格后执行 FlightSIM-test-plan.md。测试高载荷/风/延迟/电机退化，评价估计/控制能力与状态变化，不将 PC 仿真结果标为 Flight Release 或 HIL 实时性 PASS。
