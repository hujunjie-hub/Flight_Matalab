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
| P-07 | 非零杆臂旋转 | IMU/天线运动符合刚体解析式，误差≤1e-6（double理想层） |
| P-08 | 静止水平IMU | specific force=[0,0,-g]，gyro含相应 Earth 项；不把固定 N0 相对 rate=0 当 gyro 全0 |
| P-09 | 噪声 seed 重复/独立源 | 同 seed 序列相同；统计 STD 在长样本95%置信检查范围 |
| P-10 | 各 sensor delay/axis delay | sample/arrival分别正确；M2不重复补偿，计数与缺失可追溯 |
| P-11 | 地面落体/起飞 | 非负 Fn、无 NaN/Inf，最大穿透<2cm（基准场景），离地后不保持接触力 |
| P-12 | 同一500us外层内 RK4 一次500us→两次250us | 5s平滑无接触轨迹 p 差<1e-3m、姿态差<1e-4rad；控制/传感器/噪声/应用延迟不变；接触场景事件偏差≤一个500us外步 |
| P-13 | loss-of-effectiveness/外力 | 真值改变经测量反映，不能直接给 M4“传感器坏”的标签 |
| P-14 | truth 隔离 | 图依赖检查：无 truth→Nav/Control 捷径；只有 SensorSimulation、初始化和 Evaluator 例外 |
| P-15 | 几何尚未接触但快速下降 | 距地1cm、v_D=1m/s时 Fn 严格0；禁止接地之外的阻尼悬浮 |
| P-16 | 静态接触平衡 | 四角接触弹簧压缩约 mg/k；有符号 gap 为负仍有效，法向力约 mg，力矩近零 |
| P-17 | 水平接触运动 | 第一版无水平地面摩擦，水平速度不产生水平接触力或额外力矩 |
| P-18 | 惯量参数合同 | PlantParameters 保留完整 J(:)，矩阵必须对称正定；参数视图与 25 元素向量一致 |
| P-19 | 输入 fail-closed | NaN/Inf、非法布尔值、超界 rotor_effectiveness、负电机转速和非对称/非正定惯量必须拒绝 |
| P-20 | 非对角惯量耦合 | 非对角 SPD 矩阵下角加速度等于 J⁻¹(τ−Dω−ω×Jω)，不得退化为 diag(J) |

P-12 不满足须整体重选积分细化/接触参数并更新方案，不能放宽阈值；改变物理步长时保持外层时序，避免把延迟变化当收敛。P-09统计窗口可用10s以上，StopTime必须有限。

P-10 还分别覆盖固定 GNSS PVT、PPS 和历元的 sample/capture/arrival，500us释放时刻不能替代 PPS raw 捕获。T-GNSS-03..06 在同一硬件配置下抑制事件或改变有效位；generated/suppressed/released/accepted 计数及 gap 守恒，不通过移除源模型来模拟信号丢失。

P-04/05/07/08 理想层关闭噪声、地面或电机动态的具体旁路必须在 fixture 记录；生产闭环不得继承这些测试旁路。P-11 基准为地面上方0.1m、零初速、无推力落体；另设高落差场景，不能把2cm门限外推到任意撞击。P-09采用10000个独立白噪声样本，按卡方双侧95%区间检验各轴方差；固定 seed 用于回归，未通过不得反复挑 seed。q差使用 atan2 度量。

## 2. 当前脚本覆盖

verify_plant_open_loop 当前脚本覆盖 P-01..P-06、P-11、P-15..P-17、P-19..P-20。脚本生成的状态为 PARTIAL_PASS，明确列出尚未运行的 P-07..P-10、P-12..P-14。P-18 由 verify_parameter_view 检查。该函数必须在 MATLAB/Simulink 环境实际执行，静态代码审查不算测试通过。

## 3. 系统闭环评价

只在 P-01..P-20 适用项通过且共享 FCS 合格后执行 FlightSIM-test-plan.md。测试高载荷/风/延迟/电机退化，评价估计/控制能力与状态变化，不将 PC 仿真结果标为 Flight Release 或 HIL 实时性 PASS。
