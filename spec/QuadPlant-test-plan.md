# QuadPlant 验证计划

状态：全部NOT_RUN；2026-11-05。

## 1. 分级验收

先组件开环，再集成物理开环，再MIL闭环。每个结果同时记参数/模型/场景Hash、求解器、步长、frame及精度。以下阈值是SIM数学接纳值，不是实物精度承诺。

| ID | 试验 | 验收/依据 |
|---|---|---|
| P-01 | 0→5N电机目标阶跃，1s | 单调/有限，ω在5tau后距目标<1%；推力按k_f*ω² |
| P-02 | 四路相等推力 | τx/y/z残差≤1e-10Nm（double），Fz=-sum f |
| P-03 | 单前左电机1N | τx=-y、τy=x、τz=gamma，与FRD叉乘相符 |
| P-04 | 无推力/无drag自由落体0.1s，无地面 | Δv_D=g*t，Δp_D=.5g*t²，误差≤1e-6m/1e-6m/s |
| P-05 | 恒定mg向上合力，无扰动2s | v漂移≤1e-6m/s；不得重复加gravity |
| P-06 | q/-q与非零yaw初值 | 同一C_nb/物理轨迹；q范数误差≤1e-6 |
| P-07 | 非零杆臂旋转 | IMU/天线运动符合刚体解析式，误差≤1e-6（double理想层） |
| P-08 | 静止水平IMU | specific force=[0,0,-g]，gyro含相应Earth项；不把固定N0相对rate=0当gyro全0 |
| P-09 | 噪声seed重复/独立源 | 同seed序列相同；统计STD在长样本95%置信检查范围 |
| P-10 | 各sensor delay/axis delay | sample/arrival分别正确；M2不重复补偿，计数与缺失可追溯 |
| P-11 | 地面落体/起飞 | 非负Fn、无NaN/Inf，最大穿透<2cm（基准场景），离地后不保持接触力 |
| P-12 | 同一500us外层内RK4一次500us→两次250us | 5s平滑无接触轨迹p差<1e-3m、姿态差<1e-4rad；控制/传感器/噪声/应用延迟不变；接触场景事件偏差≤一个500us外步 |
| P-13 | loss-of-effectiveness/外力 | 真值改变经测量反映，不能直接给M4“传感器坏”的标签 |
| P-14 | truth隔离 | 图依赖检查：无truth→Nav/Control捷径；只有SensorSimulation、初始化和Evaluator例外 |
| P-15 | 几何尚未接触但快速下降 | 距地1cm、v_D=1m/s时Fn严格0；禁止接地之外的阻尼悬浮 |
| P-16 | Origin/Baro/地面一致初值 | p0_D=0、ground_D=.15、b_h=0；初始无噪声相对Baro预测/观测均0，地面静态压缩约mg/k，有符号gap为负仍CONTACT |

P-12不满足须整体重选积分细化/接触参数并更新方案，不能放宽阈值；改变物理步长时保持外层时序，避免把延迟变化当收敛。P-09统计窗口可用10s以上，StopTime必须有限。

P-10还分别覆盖固定GNSS PVT、PPS和历元的sample/capture/arrival，500us释放时刻不能替代PPS raw捕获。T-GNSS-03..06在同一硬件配置下抑制事件或改变有效位；generated/suppressed/released/accepted计数及gap守恒，不通过移除源模型来模拟信号丢失。


P-04/05/07/08理想层关闭噪声、地面或电机动态的具体旁路必须在fixture记录；生产闭环不得继承这些测试旁路。P-11基准为地面上方0.1m、零初速、无推力落体；另设高落差场景，不能把2cm门限外推到任意撞击。P-09采用10000个独立白噪声样本，按卡方双侧95%区间检验各轴方差；固定seed用于回归，未通过不得反复挑seed。q差使用系统测试的atan2度量。

## 2. 系统闭环评价

只在P-01..16适用项通过且共享FCS合格后执行[系统测试](FlightSIM-test-plan.md)。测试高载荷/风/延迟/电机退化，评价估计/控制能力与状态变化，不将PC仿真结果标为Flight Release或HIL实时性PASS。
