# FlightSIM 逐轮复审与方案替换记录

日期：2026-11-05；当前基线FLIGHT-MATLAB-SPEC-1.3-DRAFT；范围SPEC_ONLY。
本次新增R4/R5/R6三轮共13项，先前R1..R3共22项保留历史；累计35项。最初另有两次自审，因此作者自审累计8轮。历史行说明当时处置，当前实施只按1.3活动正文和执行协议；不是独立会签或模型通过。

## 1. 本次三轮方法与结果

| 轮 | 反例/视角 | 可执行核对 | 处置 |
|---|---|---|---|
| R4 | 约束可达性、精确终点、PID离散次序、时间轴 | D4-01..04，原短边加速度约6.71/jerk159.37；retime通过；目标/积分/双时钟反例 | 4项整体替换 |
| R5 | 授权空窗、参考连续性、重复调用、失败发布、地面停止 | D5-01..05，多种准备延迟/帧相位、grid前缀p/v/a、只提交一次、旧TTL与整数stop | 5项整体替换 |
| R6 | 地图证据、噪声源、EOF/计数、名义时间与能量 | D6-01..04，完整cell/coverage、Qc19、pending tail、30/35s时序 | 4项整体替换 |

独立递归驻点求根与Bernstein细分界另比较192组导数极值；这是有限数学/协议参考检查，不是生产算法或Simulink执行。证据见validation/semantic_reference_report.json。阶段快照及原文before保存validation/review_sessions/R4_R6，不回填旧报告假装当时已通过。

## 2. 全部追踪

| ID | 发现 | 方案替换 | 活动/历史定位 |
|---|---|---|---|
| R1-01 | M5输入与规划职责未闭合 | 完整七层制导、地图/围栏/任务/人工输入和有界Worker替换概略轨迹块 | [FlightSIM-guidance.md](FlightSIM-guidance.md), [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md), [FlightSIM-architecture.md](FlightSIM-architecture.md) |
| R1-02 | 初始REJECT与Nav一致性证据形成启动互等 | 冷启动Alignment/受控策略与故障probation拆为明确协议 | [FlightSIM-stateflow.md](FlightSIM-stateflow.md), [FlightSIM-estimator.md](FlightSIM-estimator.md) |
| R1-03 | 局部init可能复用epoch/token，source reset影响范围含糊 | LifecycleCoordinator+Owner外壳EpochStore及分域reset协议 | [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md), [FlightSIM-stateflow.md](FlightSIM-stateflow.md) |
| R1-04 | 五正交域独立决策可能提交非法组合 | 单DecisionIntent、五域协同迁移、一次Commit/副作用及稳定仲裁 | [FlightSIM-stateflow.md](FlightSIM-stateflow.md) |
| R1-05 | 原生文本PVA/对角STD无法支撑完整外部控制接口 | 未修改核心+独立逐步Launcher捕获full state/P/同刻rate，文本仅参考 | [FlightSIM-estimator.md](FlightSIM-estimator.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R1-06 | 事件排序在文档间不一致，传输容量/边界类型不全 | 唯一事件键、准确C typedef、typed batch与显式队列/拒绝策略 | [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md), [FlightSIM-data-replay.md](FlightSIM-data-replay.md) |
| R2-01 | 连续ode4/事件顺序不能由画图排列保证 | 统一fixed-step discrete、Stateflow相位协调和17维显式RK4有限步Plant | [FlightSIM-architecture.md](FlightSIM-architecture.md), [QuadPlant-architecture.md](QuadPlant-architecture.md) |
| R2-02 | 同刻求解会掩盖MPC计算/可见性延迟 | pending/active Job、固定虚拟cost/deadline和因果结果释放 | [FlightSIM-control.md](FlightSIM-control.md), [FlightSIM-architecture.md](FlightSIM-architecture.md) |
| R2-03 | 同Nav发生授权变化时可能在Frame提交旧上下文 | StateAdvance/OutputEvaluate分层，不重复积分并复核新token | [FlightSIM-control.md](FlightSIM-control.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R2-04 | Origin固定NED与当前LLH-NED/transport项混用 | 完整GeodesyAdapter和固定N0 rate约定，正式对齐留G0，不冒ABI已冻结 | [QuadPlant-architecture.md](QuadPlant-architecture.md), [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md), [FlightSIM-estimator.md](FlightSIM-estimator.md) |
| R2-05 | 初始CG/地面/Baro零基准不一致 | Origin设初始CG为0、地面D=.15、同点锁存Baro及Home相对高度转换 | [QuadPlant-architecture.md](QuadPlant-architecture.md), [FlightSIM-guidance.md](FlightSIM-guidance.md) |
| R2-06 | 接地阻尼在尚未接触时也可能产生支撑力 | 先几何门控再计算非负弹簧阻尼，禁止空中阻尼悬浮 | [QuadPlant-architecture.md](QuadPlant-architecture.md), [QuadPlant-test-plan.md](QuadPlant-test-plan.md) |
| R2-07 | 验code但Plant用未量化N会旁路M7 | code可行整数集合、逆映射N、Receipt/Plant同源、固定应用延迟及明确地面管理stop/空中失效区分 | [FlightSIM-control.md](FlightSIM-control.md), [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md) |
| R2-08 | 抗饱和可能混用旧alloc/新req并重复Receipt反馈 | 寄存完整同请求残差，首版Receipt附加AW关闭、保留匹配证据 | [FlightSIM-control.md](FlightSIM-control.md), [FlightSIM-architecture.md](FlightSIM-architecture.md) |
| R3-01 | 20ms过期/20ms周期与非零cost下99%覆盖率冲突 | job成功率99%与时间覆盖90%独立，PD衔接照常计闭环指标 | [FlightSIM-test-plan.md](FlightSIM-test-plan.md), [FlightSIM-control.md](FlightSIM-control.md) |
| R3-02 | 三入口/制导/故障测试只有概念缺独立可判定结果 | 完整运行矩阵、独立测试ID、转移目录和预置负向reason/deadline | [FlightSIM-test-plan.md](FlightSIM-test-plan.md), [QuadPlant-test-plan.md](QuadPlant-test-plan.md) |
| R3-03 | 检查失败可能残留旧PASS且漏锚点/范围引用 | 报告先失效、失败覆盖FAIL、精确锚点/区间引用/需求映射及负向自测 | [tools/check_specs.py](tools/check_specs.py), [tools/test_check_specs.py](tools/test_check_specs.py) |
| R3-04 | 并行上位契约已更新仍沿用缺字段/旧revision | 只读影响审查和准确Hash快照，整体采用Mission bit8/GeofenceConfig/0x10904，新增漂移失败 | [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md), [FlightSIM-research-and-decisions.md](FlightSIM-research-and-decisions.md) |
| R3-05 | q近零acos、RMS时刻、噪声细化和新boot重复比较口径含糊 | atan2相对q、同物理t指标、随机流独立积分调用、保留身份的语义投影 | [FlightSIM-test-plan.md](FlightSIM-test-plan.md), [QuadPlant-test-plan.md](QuadPlant-test-plan.md), [QuadPlant-architecture.md](QuadPlant-architecture.md) |
| R3-06 | 安全种子/CORE派生值/第三方包和MEX来源存在双真值风险 | 四CORE+只读Profile统一生成、复用Flight/packages/显式缓存、完整依赖与构建缓存键 | [FlightSIM-data-replay.md](FlightSIM-data-replay.md), [FlightSIM-implementation-plan.md](FlightSIM-implementation-plan.md) |
| R3-07 | 初始化/地面dwell、takeoff jerk及着陆dwell与名义时间表缺少可行余量 | CONFIGURED_PRIOR30s与STATIC_ALIGN35s分别排完整时序；显式Home/任务事务、4s起飞、23s降落并预留接地/Disarm时间 | [FlightSIM-data-replay.md](FlightSIM-data-replay.md), [FlightSIM-stateflow.md](FlightSIM-stateflow.md) |
| R3-08 | G0要求G3输出golden、G6依赖G7数据会造成阶段循环 | G0固定可用输入/接口，G2解析fixture，G3生成参考，G8再做MIL记录重放 | [FlightSIM-implementation-plan.md](FlightSIM-implementation-plan.md) |
| R4-01 | 固定短时长原语在a2/jerk5下无法启动，整段Bernstein界又使时长过度保守 | 固定端点、0.2s整数retiming和深度4导数界细分，真实T计入key/g | [FlightSIM-guidance.md](FlightSIM-guidance.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R4-02 | 非格点任务终点可能永远落不到接受半径 | 精确GoalConnector及固定GoalRecord；连接器计入新路径段数/时间容量 | [FlightSIM-guidance.md](FlightSIM-guidance.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R4-03 | 先更新I再输出以及额外残差一拍延迟改变父PID离散律 | Read I[k]→Evaluate/Allocate→Validate→Commit I[k+1]，首次seed、失败不污染历史 | [FlightSIM-control.md](FlightSIM-control.md), [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md) |
| R4-04 | 物理仿真时间与FCU重启时钟混用，旧记录重绑定不完整 | Simulation/FCU双时间轴、完整RunBinding、物理数据重发布与历史授权隔离 | [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md), [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md), [FlightSIM-data-replay.md](FlightSIM-data-replay.md) |
| R5-01 | 先改Directive后等参考会在飞行热切换中产生授权空窗 | 准备/活动双通道；保留身份、候选验证后一次ActiveContext提交，硬撤销独立立即执行 | [FlightSIM-stateflow.md](FlightSIM-stateflow.md), [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md), [FlightSIM-architecture.md](FlightSIM-architecture.md) |
| R5-02 | 异步旧根/抖动anchor/延迟授权会破坏参考切换连续性 | 原子有界Host规划、不可变家族grid、60ms相同前缀与未来交接，迟到丢弃重算 | [FlightSIM-guidance.md](FlightSIM-guidance.md), [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md) |
| R5-03 | 准备/重复调用可能多次积分人工yaw和高度 | 预览工作副本与活动状态分开，唯一输入事务只提交一次 | [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R5-04 | 失败后保留旧状态但刷新Header会把失效导航伪装新鲜 | 失败原子发布，Nav原时间/TTL保持，Health诊断独立更新 | [FlightSIM-estimator.md](FlightSIM-estimator.md), [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md) |
| R5-05 | 地面stop瞬间跳零违反slew，DISARMED后仍发油门语义冲突 | DISARMING签发150ms证书，整数码有界降至零目标已应用后才DISARMED | [FlightSIM-control.md](FlightSIM-control.md), [FlightSIM-stateflow.md](FlightSIM-stateflow.md), [FlightSIM-execution-protocol.md](FlightSIM-execution-protocol.md) |
| R6-01 | 有限对象观测不能表达4096cell自由空间证据 | 完整调查快照/覆盖mask与最多8动态对象分路，Host来源不伪装公共传感器 | [FlightSIM-guidance.md](FlightSIM-guidance.md), [FlightSIM-architecture.md](FlightSIM-architecture.md), [FlightSIM-interface-contract.md](FlightSIM-interface-contract.md) |
| R6-02 | P0/过程平稳STD/PSD及rate到delta统计假设未完整区分 | 分别定义P0、白噪声PSD、GM驱动及Baro RW，并固定右矩形增量适配和其误差/统计适用范围 | [FlightSIM-estimator.md](FlightSIM-estimator.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R6-03 | 低频最后记录/延迟尾部被误当EOF，采样与消费计数混用 | 逐stream coverage/计划/Hash/gap/end_reason及边界计数守恒 | [FlightSIM-data-replay.md](FlightSIM-data-replay.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |
| R6-04 | 保守时长与名义任务时间未实算，30s能源fixture不能覆盖35s/重启 | 细分界下显式时序检查；能源用global seconds并覆盖RunInterval，不随FCU重启归零 | [FlightSIM-data-replay.md](FlightSIM-data-replay.md), [FlightSIM-stateflow.md](FlightSIM-stateflow.md), [FlightSIM-test-plan.md](FlightSIM-test-plan.md) |

## 3. 落地边界

HostNative V2的clock、grid、pending/active、retimer、World证据和数值提交均已选定，不留实现者在旧/新方案之间自由切换。G0-HOST仍要验证依赖、真实输入与生成schema，G1仍要实际compile最小拓扑，后续全部模型测试NOT_RUN。

固件等价声明单独经过FirmwareConformanceGate；Host方案不同于上位原primitive/Port组合语义之处已明确列出，不把复用C类型当数值/时序兼容证明。原FMT-Model、父spec/固件/驱动和官方资料本轮均只读。

## 4. 用户澄清后的GNSS/PPS目标纠正

这不是新增自审轮次，不改写R1..R6的历史结论。用户确认UM982/PPS为主要固定器件，原意为飞行中GNSS信号丢失；因此整体替换可选器件/默认无GNSS解释。

| 范围 | 本版固定方案 | 验证边界 |
|---|---|---|
| 产品/Manifest | GNSS/PPS安装与启用均固定true，不将现有固件关闭状态当设计目标 | 配置观察有源Hash；本次未改固件 |
| 运行/恢复 | PVT、PPS、UTC历元独立质量；失锁不停止IMU/本地时钟、不改安装位，不自动恢复已暂停任务 | T-GNSS-02..06，模型NOT_RUN |
| 仿真/回放 | 名义含三路证据，35s失锁/恢复场景保留gap；ExtINS须在参考生成时移除真实PVT更新 | 不给健康Nav贴失锁标签，不补造历史PPS |
| 实施差异 | 初始BSP关闭观察已保留历史；当前固定接入已同步，原生GNSS parser/UTC/标定未接纳仍明确列出 | FirmwareConformanceGate未关闭 |

详细决定见[研究第11节](FlightSIM-research-and-decisions.md#11-gnsspps固定器件与运行失锁纠正)与[执行协议第8节](FlightSIM-execution-protocol.md#8-固定gnsspps与运行中失锁)。原有13个参考用例不冒充新增GNSS模型测试PASS。

## 5. 独立目录迁移

2026-11-05按用户要求将工程移到与Flight同级的Flight_Matalab，已有规格/工具/历史证据全部随目录迁移。当前上位链接改到同级Flight/spec，原模型链接改到同级FMT-Model，检查命令从本工程根执行。算法方案及先前审查轮次不变；迁移核对不等于模型编译/仿真。准确路径、原文件Hash及当前检查见[迁移记录](validation/project_relocation_report.json)。
