# FlightSIM M5制导与规划设计

状态：HOST_NATIVE_V2设计规格；2026-11-05。职责、公共值消息和硬约束继承父04/02；本版以约束驱动的边时长、精确目标连接及原子Host规划替换固定短时长primitive/异步候选方案。V2内部算法差异需经FirmwareConformanceGate后才能声称固件等价。

## 1. 七层边界

FMT_M5_Guidance.slx为ReferenceInputAdapter→LocalMapManager→PathPlanner→TimeParameterizer→MinimumJerkOptimizer→TrajectorySafetyValidator→ReferenceLifecyclePublisher。有限固定维数内核可用MATLAB Function，生命周期用Stateflow；M5不推进Mission、不授Authority/Permit、不做MPC。

输入锁存M45-01的明确target_valid_mask/target、Nav/Capability、准备上下文或活动上下文、SafetyEnvelope、LandedState、授权人工/当前任务、Permit、围栏、环境/障碍及Clock。目标mask/来源按接口第8节，失效目标拒绝；M5 mass/gravity由ProductGuidanceConfigPayload的共享车辆视图给出，不能从总推力反算或使用1kg helper默认。活动输出与准备候选分槽；M6只消费与M4 ActiveContext配对的参考，不能把最新候选当活动参考。

## 2. 原子Host规划

Host功能MIL在20ms规划/发布槽内按不可变快照一次有界执行完整数值链；期间虚拟Clock不推进，PC墙钟单独记录。这是非实时Host执行选择，不再使用会把80ms旧Nav根直接发布的0.5ms M5 Worker。

先尝试根→精确目标的连续五次直接连接，硬约束/连续碰撞全部通过才接受；否则进入有界A*。搜索后时间参数/固定时长minimum-jerk及最终消费曲线验证全部完成才READY。无完整解就拒绝，不发表部分路径。原子调用有限但不承诺H723 WCET；规划延迟故障通过候选可见性/截止注入，迟到结果过期即丢弃，下一合法槽从新快照完整重算，不给旧候选换时间头。

## 3. 约束驱动的lattice

保留父04的方向/velocity/yaw bin、完整含time的key、Node512/Open512、Hash1024、Closed/parent_primitive及稳定比较规则；父60个primitive仅作为端点提案种类。原0.2/0.4s等duration是V2最小种子，不再直接决定边时长。

1. 固定候选终点p/v/a/yaw：先由原primitive种子提出端点，再按原网格中心规则量化；之后增加T不能重新移动终点，不能只换key丢连续状态。根为交接参考状态或首条捕获参考状态，导航只作新鲜度/跟踪/不确定度证据。
2. 对每轴从端点p/v/a求唯一quintic，T以0.2s tick表示。首次T取primitive最小时长与距离/速度/加速度/jerk下界的较大值，向上取tick；不通过则ticks=ceil(5*ticks/4)，最多16次，边/剩余路径时间受总容量限制。
3. v/a/jerk先转Bernstein控制系数，用de Casteljau二分收紧凸包界，每个导数最多深度4/16叶。任一界缺失或最终仍越界就拒绝该时长；有限细分不能改成仅采样点通过。方向/推力/倾角等线性或范数约束再按当前包线验证。
4. 实际接受T决定time_bin增量和g，不能仍用原primitive的短duration记搜索代价。WAIT只在静止canonical节点生成并保持同一位置、进入新time_bin；非canonical根不生成被吸到格心的假WAIT，合法保持由活动参考完成。parent节点key差和parent_primitive可重建真正端点/时长。每节点最多64边检查包含GoalConnector，单次最多512扩展，容量耗尽返回明确原因。

网格中心不能代替任务终点：每展开节点可增加一条GoalConnector，连接正式目标p/v/yaw并用同一有界retimer及连续验证；目标不进lattice哈希，单独固定GoalRecord保存端点/时长/parent。达到目标必须在acceptance_radius且满足末端速度/航向，不能吸附网格后报完成。SIM回归半径0.2m，终端速度0；含3个0.25m轴偏差的最近中心误差0.433m不能被当成成功。

总轨迹程序≤8段：最多3段不可改的交接前缀，最多5段新路径（包含GoalConnector）；新路径time_bin≤30、≤6.0s，总时长≤6.2s。超出不截断成功。Minimum-jerk只优化新路径内部v/a，前缀及其交接p/v/a固定。失败仅可使用同路径、已独立验证的初始quintic。

## 4. 参考窗口与模式

public预览仍anchor+24点、20ms间隔、480ms，消息lease≤40ms；参考grid/交接与M4准备提交详见[执行协议](FlightSIM-execution-protocol.md)。每次rolling都验证实际消费Hermite曲线。新语义更换reference_epoch；同一程序滚动只换Header.sequence，不能用旧程序续命。

首次Arm的默认MANUAL_RATE/零throttle输出typed Pilot参考；不跑零长度A*。MANUAL_ATTITUDE/人工ALT_HOLD依父02/04人工姿态/三点throttle/垂向参考律，预览不可改变活动yaw/高度积分。POS_HOLD/任务/RETURN及完整位置着陆使用MotionReference；Home由M4持有，M5不自行更新或推进任务。

LAND/ALT_HOLD采用上位新增ALTITUDE_AUTOMATIC=5，仅发布垂向typed参考，不填虚构XYZ。独立一维quintic从新鲜Nav垂向p/v及有效a建立首段；a无效时以参考a0=0播种，不修改Nav。每段下降最多1m、终点v/a=0，下一段沿上一参考终点连续连接；有效Home时不下降至Home以下，可靠LANDED时保持。每段用本版0.2s整数retimer及相同v/a/jerk/推力/倾角检查，最多16次、总时长≤6.2s，容量失败明确拒绝。姿态参考为零roll/pitch和段入口锁存yaw，yaw_rate_ff=0；载荷高度Up=-p_D、速度Up=-v_D。数值进展/准备副本仍遵守唯一State Time提交，不积分摇杆。存在需证明围栏时拒绝此分支；默认围栏Profile不会因导航丢失自动关闭围栏，专门的无围栏故障夹具才验证该分支。

## 5. 地图和连续验证

SIMULATION/STATIC_MAP启用完整地图；NONE只允许requires_obstacle_avoidance=false的任务，并报告OBSTACLE_ASSURANCE_UNAVAILABLE。不得把源失联动态降为NONE。地图证据不再借8条ProductObstacleObservation填充4096个FREE cell。Host默认采用SimWorldEvidenceAdapter：从有Hash的显式已知世界调查生成SimSurveyedMapSnapshot（cell_state:uint8[4096]、coverage_mask:uint8[512]、分辨率/世界变换、world_revision、global有效区间、Origin/state绑定）；M5验证完整后一次安装。部分/缺失覆盖保持UNKNOWN，空障碍列表不产生FREE。静态/动态世界几何均为外生场景，不读取Plant当前p/q；换Origin须按公开Origin和已知World锚点重新变换生成，不能只换ID。

默认16^3×0.5m窗口[-4,4)m。显式SIM_KNOWN_WORLD假设下每250ms确认同一world_revision有效并刷新500ms证据；世界改变须先生成新完整快照，发布前旧快照按原期限处理，不能用心跳证明真实世界没有变化。ONBOARD_SENSOR仍UNSUPPORTED。SimDynamicObjectBatch最多8个对象/调用、track最多8条，独立携带global sample/expiry、预测边界和不确定度；预测至少覆盖当前480ms消费窗口及规定年龄。Host私有source key不塞进公共sensor_instance_id或伪造已接纳传感器。

真实/兼容M2 ProductObstacleObservation是另一个只在来源正式登记后可用的入口，仍受≤8条限制；它不自动具有“空体积已测绘”语义。两个入口统一到M5内部地图/track证据，不改变公共C类型，不将Host已知世界当真实感知接纳。

连续Validator独立于搜索/优化：检查frame/所有epoch/时效、v/a/jerk/推力/倾角、围栏和碰撞。24个消费区间，每区间细分深度≤5、总工作单元≤256。缺保守界、未知空间或容量不足即REJECTED/UNKNOWN。

新路径准备前比较Nav与活动参考在Control Time的p/v，偏差超过0.5m/0.5m/s则拒绝该普通交接并交M4；当前轨迹几何膨胀包含0.5m跟踪偏差预算，不能只考虑滤波STD。

SIM_ONLY：车辆球0.35m、margin0.10m、位置/速度STD膨胀系数3、反应延迟0.10s、最小制动加速度1m/s²；视距按v²/(2a)+v*t+margin。围栏N/E[-3.5,3.5]m、Home高度[-1,3]m，Home/Origin变化重验。已知支持面与批准的Home半径0.5m接地点独立约束，TAKEOFF/LANDING最多2cm穿透，其他任务不得穿地；不把地面排除偷换为任意地面FREE。

## 6. 验证重点

固定短边反例、细分Bernstein界、retimed time_bin、非格点GoalConnector、直接连接被障碍拒绝后进入真实A*、容量/期限、三段前缀与五段新路径上限必须分别测试。至少一个强制A*自由空间工况和一个障碍工况成功，不能仅用直接连接证明A*。不同搜索测试Profile的约束明确记录；默认jerk5/a2的首边必须通过，不能靠放宽默认限制掩盖旧问题。
