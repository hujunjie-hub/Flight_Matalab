# FlightSIM Stateflow状态机设计

状态：设计草案；2026-11-05。公共状态数值从[父ICD](../../Flight/spec/02_接口契约与公共数据规范.md)生成，操作守卫继承[父06](../../Flight/spec/06_FMS通信与系统安全设计.md)。本版采用活动/准备双通道、事务提交与分阶段启动协议。

## 1. 五域事务协调

M4的FmsStateCoordinator Chart顶层AND，包含五个OR域；各域只写本域next状态，所有守卫读同一PreviousFmsState和不可变事实快照。Stateflow中的Arbiter先选择一个DecisionIntent（事件、原因、请求身份、必需安全动作），再按Failsafe→Arm→Authority→Mission→Mode依次运行域。DecisionIntent不预计算另一套状态；迁移规则仍在Chart，所有域依据相同事务事件协同转换。

| 域 | 状态，首项初始 |
|---|---|
| Arm | DISARMED、ARMING、ARMED、DISARMING |
| Mode | NONE、MANUAL_RATE、MANUAL_ATTITUDE、ALT_HOLD、POS_HOLD、AUTO_MISSION、AUTO_RETURN、AUTO_LAND、EMERGENCY_LAND |
| Authority | NONE、PILOT、MISSION、GCS_SUPERVISED |
| Failsafe | NORMAL、DEGRADED、ACTION_REQUIRED、TERMINAL |
| Mission | IDLE、LOADED、RUNNING、PAUSED、ABORTED、COMPLETED |

执行外壳为SnapshotLatch→Arbiter→TransitionCoordinator→五域CommitAndEpoch→ActiveContext发布。普通切换先在私有PendingContext准备，五域只在COMMIT时同步生效；详见执行协议。副作用（任务推进、epoch递增、ACK、Permit安装/撤销）仅Commit一次。五域不能直接写M7，不得依赖域顺序偷读别域新状态。提交不变量失败是实现缺陷，测试立即FAIL并中止，不能留下Chart与公开状态不一致。

同tick硬事件、周期事件、普通请求合并为一次事务调用。优先级：硬输出/强安全约束→TERMINAL→已登记安全动作→显式Pilot接管→一个普通请求；同级按事件时间/source/request排序。被安全动作取代的已接纳长操作取消并给原因，未选择请求保持原TTL等待。请求队列4、长操作4、幂等cache32/60s；同键同payload只回放ACK，同键异payload拒绝。

普通热切换Chart内部为IDLE/PREPARING/READY_TO_COMMIT/ABORTED；不新增公共FlightMode枚举。准备上限80ms，READY在下一500us事务触发复核/提交；活动Permit/Reference在此之前仍配对。准备取消不回收保留的epoch/token。硬撤销立即生效，不能排队等候选。

## 2. 事务迁移和不变量

| Intent/前置 | 各域协同结果和输出 |
|---|---|
| ARM_PREPARE，DISARMED且新鲜PreArm PASS | Arm→ARMING；Mode保持NONE；无运动Permit，M5开始验证保持候选 |
| ARM_ACTIVATE，ARMING且地面证据/READY/bundle全匹配 | Arm→ARMED、Authority与已批准模式同时安装；先IDLE_ONLY再按握手CONTROL_ACTIVE |
| ARM_CANCEL，条件失效或绝对100ms到期 | Arm→DISARMED、Mode→NONE、Authority→NONE，撤销并结束请求 |
| DISARM_BEGIN，可靠LANDED及dwell | Arm→DISARMING，撤销控制；M7完成GROUND_STOP至零目标已应用且无活动帧后DISARM_DONE |
| DISARM_DONE | DISARMED/NONE/NONE；任务不得仍RUNNING，按请求语义PAUSED或ABORTED |
| PILOT_TAKEOVER，新鲜RC显式边沿/登记手势 | Authority→PILOT、Mode→请求允许人工模式，运行任务→PAUSED；同Commit换authority/reference关联并撤旧Permit |
| MISSION_START/RESUME | 正式任务epoch/当前项token、导航和可行候选匹配，Mission→RUNNING、Authority→MISSION、Mode→AUTO_MISSION |
| MISSION_PAUSE/ABORT/COMPLETE | Mission进入相应状态；同事务选已验证HOLD/LAND等合法模式及Authority，撤旧任务参考；无能力时安全终止 |
| SAFE_ACTION/TERMINAL | Failsafe与Arm/Mode/Authority共同遵守产品动作；M7撤销先行，不能保留RUNNING旧任务授权 |

DISARMED/DISARMING不得发布CONTROL_ACTIVE；ARMING软件输出抑制；RUNNING必须有匹配Mission Authority/Mode/token；任何Mode所需能力不足不得签对应Permit。POS_HOLD要求Origin/水平能力、不无故要求Home；RETURN额外需要Home/路径/能源。ALT_HOLD不要求XYZ MPC。

AUTO_LAND/EMERGENCY_LAND在水平能力或Home不满足时，只能由M4明确选Directive LAND/ALT_HOLD及GuidanceReferenceKind=5；任务退出RUNNING、自动token清0，不把该typed载荷误当人工接管。仍必须具备垂向p/v、姿态/角速度及完整包线；无水平保证且存在待证明围栏则拒绝并按当前Host输出策略处理。普通ALT_HOLD仍是Pilot授权的kind4，不可混用。M4的既有操作授权/安全动作决定Authority，typed载荷本身不改变Authority。

普通Mission/模式/换项均经PREPARE后COMMIT，禁止先把新Directive发给M6、再等待M5参考造成授权空窗。首次握手：M5 READY→M4匹配Permit→M6执行→M5 ACTIVE，不以ACTIVE反向作为首Permit条件。IDLE_ONLY每次≤25ms且仅凭新鲜地面证据续租；首参考绝对100ms不续延。Mission Commit只装载LOADED，不自动Start，≤32航点；M4唯一推进当前项。

## 3. 冷启动与源健康协议

冷启动与故障恢复分开。初始化不得要求先存在活动Nav的NIS才能让唯一IMU启动，也不得缺策略直接开放自动控制。

1. NEW_RUN所有源UNKNOWN/REJECT，M2仍采集/校验并向独立Alignment输入提供合格原始事实；该路径不发布可控Nav。
2. 已验证SIM配置、自检、样本连续性/校准/时间通过后，DISARMED的InitializationCoordinator请求源级INITIALIZING策略。唯一IMU由Integrity签发受控DEGRADED初始化许可；辅助源可供初始化的磁场/静止先验检查，但活动融合仍须有效策略。
3. Alignment使用明确WGS锚点、充分静止证据、重力roll/pitch及合格Mag或显式已知heading先验。使用场景初态播种时标为CONFIGURED_PRIOR，不记作传感器独立测得。没有heading证据则能力保持未建立；静止gyro bias估计先扣除姿态/地点对应Earth rate，不把地球自转当零偏。
4. M3在工作副本创建InitState/P/Origin，验证后一次提交；初始化成功不直接解锁。Integrity依据M2证据与可用诊断进入DEGRADED，再按固定稳定窗口升HEALTHY。FMS等待所需能力、地面dwell和PreArm，Nominal Arm仅在这些成立后成功。
5. CONFIGURED_PRIOR默认fixture在首批合格样本后100ms内建Nav，静态对准fixture最晚2.5s建Nav；后者仍需从有效Nav起另累积2s地面dwell，Arm设在5s。超时明确FAIL并保留证据；禁止把健康强制置TRUE。恢复按下述probation路径，不复用初始化捷径。

QUARANTINED/FAILED保持REJECT；M2硬证据恢复后进入RECOVERY_PROBATION，REJECT+ALLOW_SHADOW_EVALUATION，新policy_epoch。M3诊断副本只产SensorConsistencyEvidence，不更新活动状态。门槛：IMU 5样本/50ms/500ms timeout；Baro/Mag 5/100ms/1s；GNSS 5/1s/5s；先DEGRADED（R×4），连续2s且20合格样本后NORMAL。FAILED只在地面维护清除；单IMU无有效姿态只能地面受控重新初始化，空中不承诺恢复。

FDIR按10Hz刷新、TTL300ms。最后REJECT保持；缺/过期辅助策略REJECT；最后NORMAL/DEGRADED且M2仍有效的唯一IMU仅按父05保留有限姿态类传播并报FDIR_UNAVAILABLE，不能把全部源恢复HEALTHY。

## 4. 时间、恢复与附属Chart

所有Chart为离散事件/周期调用；TTL/deadline/dwell直接用同一boot/time epoch内FcuClock的uint64 evaluation_time/state_since，不用after(N,tick)代替墙钟。周期与提前事件合并，一tick最多一次FMS事务；长操作期限与输入队列TTL分开。PreArm固定15项ID0..14，UNKNOWN/FAIL必需项拒绝，逐项证据可追溯。

| Chart | 状态/职责 |
|---|---|
| M1 LinkMonitor | UNKNOWN/INITIALIZING/HEALTHY/DEGRADED/LOST/RECOVERING；只报事实 |
| SensorIntegrity | UNKNOWN/INITIALIZING/HEALTHY/SUSPECT/DEGRADED/QUARANTINED/FAILED/RECOVERY_PROBATION；源级Owner |
| TimeReferenceMonitor | 固定GNSS/PPS的LOCAL_ONLY/ACQUIRING/LOCKED/HOLDOVER/DEGRADED/INVALID监督；UTC质量与本地时基状态分别输出 |
| M5 ReferenceLifecycle/Planner | 参考INACTIVE/READY/ACTIVE/HOLDING/REJECTED/EXPIRED；规划事务见制导设计 |
| M7 OutputLifecycle | DISARMED/ARMING_IDLE/ACTIVE/HOLD_GRACE/SAFE_ACTION/FAULT_LATCHED；不自签Permit |
| M4 LandDetector | UNKNOWN/LANDED/IN_AIR/TAKEOFF/LANDING；只消费有效产品测量/Nav/ActuatorStatus |

RC lost=300ms、recovery=500ms为SIM fixture；接收机failsafe硬位立即生效。恢复/回中没有接管边沿则不变Authority；GCS/Companion丢失只影响依赖操作。TERMINAL清除仅DISARMED、可靠地面、明确维护请求、完整健康检查同时满足；恢复不自动清任务/Home/Failsafe。

GNSS/PPS固定安装及启用，不因失锁迁移为NOT_INSTALLED。GNSS导航、PPS捕获、UTC历元分开监督；冷启动无Fix/未锁定与飞行中曾有效后丢失不同。TimeReferenceMonitor只报时间事实，GNSS PVT不可用由SensorIntegrity处理，M4按M3实际能力选择动作；PPS单独丢失不直接触发姿态失效/全局time_epoch重建。完整阈值、恢复与不自动续任务规则见执行协议第8节。

局部stop/init由LifecycleCoordinator执行，epoch高水位留在外壳；具体域见[接口生命周期](FlightSIM-interface-contract.md#6-生命周期协议)；双通道/参考grid/预览副作用/地面停止唯一详见[执行协议](FlightSIM-execution-protocol.md)。

## 5. Host输出policy2

仍有可靠导航且M4可授权时，M4选择正常M5/M6链的受控降落。失去授权/导航后M7不得自行造降落推力。DISARMED、ARMING和经验证的普通地面Disarm是有意抑制输出的正常阶段，不要求Control Demand，也不触发缺Demand故障。运动控制已生效且仍要求持续控制时，若无法形成合法帧才发SimStopEvent，MIL在下一物理积分区间开始前终止；这只证明拒绝非法提交，不代表物理着陆安全。负向用例必须命中预期原因和时间窗口，名义场景任何此终止均FAIL。

正常Disarm在DISARMING撤销新运动帧，凭M4签发的150ms GroundStopCertificate执行M7有界降推力，最坏105.5ms到零目标已应用且帧排空后才DISARMED；电机自然衰减可继续记录，不能冒称已测得转速为0。管理停止不冒充ActuatorDemand/Receipt、不清撤销水位，且只有经LANDED验证的普通Disarm/初始抑制可走该路径；空中失效仍SimStop。

HOLD_GRACE仅在原Demand/Permit仍有效且产品策略允许的窗口内保持，不延长任何expires；SAFE_ACTION无法取得合法M4控制时进入上述SimStop。回放可继续记录拒绝事件，physics_closed_loop=false。

## 6. 名义SIM策略及验收

CONTACT、|v_D|≤0.15m/s、|a_D|≤0.5m/s²连续2s才LANDED；NO_CONTACT或|v_D|>0.3m/s持续200ms为IN_AIR。每项有效且同上下文，缺CG加速度证据UNKNOWN。初始不能由Chart直接写LANDED。

能力STD上限：attitude10deg、heading15deg、XY位置1.5m、Z位置0.75m、速度各0.5m/s；进入阈值×0.8/dwell100ms，退出超上限立即退化。合成EnergyProvider：battery_fraction=clip(0.9-0.001*t_sim,0,1)（Simulation Time秒），有效区间覆盖整个RunInterval（默认30s、静态对准35s），FCU reboot不重置能量；return=0.2、land=0.05，TTL100ms；未启用则ENERGY_UNKNOWN。

每个OR域default唯一；合法迁移、非法组合、同tick竞争、ACK幂等、冷启动与恢复分别测试；转移覆盖率及未覆盖原因列报告。当前编译/模型测试NOT_RUN。Mission命令按当前上位ProductOperationPayload.mission_epoch与valid_mask bit8实施；字段已定义，后续仍需选定Product/Port基线和ABI验证，不再保留缺字段旧方案。
