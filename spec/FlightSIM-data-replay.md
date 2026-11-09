# FlightSIM 数据、回放和场景契约

状态：设计草案；2026-11-05。与[公共接口](FlightSIM-interface-contract.md)共同约束三个入口。

## 1. 唯一导入边界

禁止模型依赖base workspace中碰巧存在的imu/ins/fms变量。规划导入工具先验证数据与manifest，生成有版本的RunDataset MAT及Simulink.SimulationData.Dataset，运行器通过SimulationInput显式注入。

| manifest字段 | 必需含义 |
|---|---|
| dataset_id / dataset_sha256 / source_files | 原始文件与Hash，未找到文件则失败 |
| RunBinding / coverage | source/global/FCU映射、各stream覆盖区间/计划/预期数/gap/end_reason |
| input_level | RAW_SENSOR、M2_STANDARD或EXTERNAL_NAV，互斥 |
| clock / time_scale / t_ref0 / mapping / boot_segments | 单位、历元、周回绕/重启及转换证据 |
| sample_time_definition / arrival_time_definition | 物理中心/DRDY/到达分别定义，不能混名 |
| frame / quaternion_order / quaternion_direction | NED/ENU、FRD/FLU与q约定 |
| reference_point / lever_arms / altitude_datum | IMU/CG/天线、杆臂、椭球/AMSL/压力高度 |
| units / rate_or_increment / covariance_kind | 每列单位、rate或delta、STD或variance |
| profile / core_hash / calibration_version | 绑定配置，不能只凭文件名选参数 |
| receiver / pps / utc_evidence | 固定UM982及PPS启用事实；PVT、边沿、历元的独立事件/质量/配对/缺口；不以一个gnss_available表示三者 |
| random_seed / faults / expected_outcome | 可重复的噪声、故障和预期结束原因 |
| finite_start_us / finite_stop_us | 有限区间，默认30s；超数据范围拒绝 |

每个typed stream用结构化数组保存sample_time_us:uint64[N,1]、arrival_time_us:uint64[N,1]、sequence:uint32[N,1]及完整messages；索引列须与消息Header一致。消息与时间列不维护两个独立真值。NaN/Inf只允许在导入错误报告，不能进入控制。

## 2. 三条输入路径

- RAW_SENSOR：manifest明确SIM_RAW_ENGINEERING或RAW_CAPTURE；前者为sensor轴工程量虚拟采集，后者含真实格式字节/描述符，二者不能互冒解码覆盖；单位转换→M2安装/标定/时间修正→M3；不得提前扣一次bias后又在M2重复扣。
- M2_STANDARD：已经是合格的标准样本，M2只验证并转发；CALIBRATED和pipeline修正不得再施加。
- EXTERNAL_NAV：先离线参考/外部结果适配，按其来源时间映射与参考点证明重建Nav bundle；不执行内部M3融合。

数据集缺arrival时间时可选SIM_IDEAL_ARRIVAL派生测试数据，但必须标为合成传输假设；该数据不用于真实延迟/20ms接纳验收。历史publish时间不得直接冒作physical sample time。

## 3. RunBinding、释放与覆盖边界

所有物理/源事件用Simulation Time global_us排序，到达向上量化到500us；公共消息时间由RunBinding映射到当前FCU local，boot/source reset按[双时间轴协议](FlightSIM-execution-protocol.md#1-双时间轴)处理。原时标、原Header和映射证据不可改写；新发布测量/Nav与历史授权分开处理。

唯一事件键为(arrival_global,sample_global,source_id,sequence,ingest_ordinal)。M3融合另按原sample/journal顺序；不以release替代sample。Source队列和已发布FCU消息队列分开：新boot清旧业务消息，但不会清掉尚未发生的未来场景global事件。

每个stream声明coverage_global_interval、采样/事件计划、预期记录数、已知gap清单、end_reason及完整文件Hash。覆盖区间不等于最后一条记录时刻：10Hz GNSS在29.91s最后到达仍可完整覆盖[0,30)s；不得因为cursor到文件尾就提前结束全模型。缺失应到达记录、未声明gap、Hash/计数错误或意外截断才FAIL。

Run为[0,T_stop)，T_stop只记终态不释放/积分。生成于Run内但global release>=T_stop的样本属于pending tail，原始记录和future arrival仍保存供下一次导入审计，不虚报已消费。回放首次传播所需previous-IMU/捕获历史在manifest明确提供或记录初始化缓存，不能复制第一条造前样本。

计数按边界记账：generated分为source-drop、release-overflow、epoch-discard、released、pending-tail；released再分M2 accepted/rejected。M3调用另记previous-cache/initializing/propagated/rejected，M6另记NumericCommit/ContextEvaluation/skip，frame_due另分CONTROL/IDLE/GROUND_STOP/INHIBITED/REJECTED。不同层频次不互当验收值。

## 4. 参数、结构和依赖的唯一来源

SIM_ONLY四份CORE为vehicle_model.yaml、sensor_alignment.yaml、estimator_tuning.yaml、controller_tuning.yaml。实物数据只引用同级`../Flight/applications/config/QUAD_X4`（相对ProjectRoot）的路径/Hash，未接纳值不自动导入；可用性以G0重新核验为准，不把此前两文件观察当永久清单。

同目录的profile_manifest.yaml是编译期结构/安全契约，不是第五份可调CORE。它持有初始化模式/先验来源、源启用、Host V2执行协议/参考grid/retimer、FMS/Integrity/Guidance策略种子、围栏定义、队列/虚拟预算和output_policy2。Plant接触/电机物理量属于vehicle_model；环境/故障属于scenario。固定数据映射生成ProductFmsConfig/ProductGuidanceConfig/ProductGeofenceConfig等只读视图；块Mask不再手填第二份值。

本产品Manifest固定receiver=UM982、gnss.installed/enabled=true、pps.installed/enabled=true；生成器拒绝缺字段/false，不继承旧BSP_FLIGHT_GNSS可选开关；native_backend=DISABLED只记录尚未接纳的协议实现，不能覆盖固定器件目标。MIL采用SIM_PVT及SIM_PPS_EPOCH两个明确合成适配路径，DataSIM消费记录中的对应事件；这不代表UM982原始串口解析已完成。故障脚本只改变PVT输出/validity、PPS边沿和历元质量，不修改安装/启用位、Kconfig、aiding_mask或源ID。GNSS采样模型和启用配置仍在场，停包段保留计划并用declared gap说明。

YAML经离线校验生成规范JSON与.sldd；固定schema/单位、拒绝重复键/NaN/Inf、源SHA256与生成器Hash同时绑定。Hash不包含自身hash字段；派生杆臂/矩阵只计算一次，源变更使所有视图失效。MATLAB消费生成结果，不在步进中解析YAML，不假设readstruct支持YAML。

依赖只在external_dependencies.lock.json登记完整commit/源包Hash/许可证/构建选项。公用包优先只读解析同级`../Flight/packages`（相对ProjectRoot）；没有合格包时由显式准备工具放入FLIGHTSIM_DEP_CACHE专用缓存，禁止复制另一套到Flight_Matalab/third_party。交付目录只保留锁、来源声明及本项目适配代码；Pristine MATLAB核心在隔离job解析缓存，OSQP生成/MEX在work，Hash/编译器/MATLAB release/架构/精度/稀疏模式共同决定缓存键。离线缺包立即报依赖未就绪，不能切换算法补过。

## 5. 标准30s合成场景

| 时间s | 事件 | 数据/预期 |
|---|---|---|
| 0..2.5 | CONFIGURED_PRIOR初始化/接地dwell | 完整合成初态/先验STD明确，首批样本后100ms内Nav可用；2s有效地面dwell实际累积，不称为重力测得yaw |
| 2.6 | DISARMED SET_HOME | M4捕获新鲜Nav，装载Home相对高度围栏，重做PreArm |
| 2.65..2.9 | Mission staging/Commit | 两项N/E航点[2,0]、[2,2]m、高度Home上1m，LOADED但不Start；source/session/transaction/hash匹配 |
| 3 | Arm request，MANUAL_RATE/零throttle | PreArm与地面证据有效，typed RATE零输入候选/Permit握手≤100ms，保持地面 |
| 4 | TAKEOFF 1m above Home | M4授权GCS_SUPERVISED/POS_HOLD路径，有限五次轨迹及稳定时间在7s前完成 |
| 7..10 | 悬停 | RMS评价窗口 |
| 10..18 | Mission Start/两航段 | 请求带已提交任务的当前epoch；M4逐项推进，17.5s前完成两项，再合法HOLD |
| 18..23 | RETURN/Home保持 | Home/Origin/token有效，22.5s前到Home并稳定；能力不足拒绝位置返航 |
| 23..30 | LAND/Disarm/地面stop | 合成下降上限0.6m/s，目标27s前接地，留接触稳定和2s dwell；M4可靠Disarm后M7管理stop，30s未完成FAIL |

默认30s选择CONFIGURED_PRIOR，避免2.5s静态对准结束后才开始2s LandDetector dwell而与3s Arm冲突。独立STATIC_ALIGN_35S用2s静止窗口、最晚2.5s建Nav、最晚4.5s可靠LANDED、4.6s Home/任务准备、5s Arm，其后运动事件整体延后2s，StopTime35s；不能把对准期间的无效Nav算进地面dwell。

上述两套名义场景始终包含GNSS 10Hz、PPS 1Hz及独立有效历元流。PPS在global整数秒捕获，首个边沿在0s，8个合格间隔在配对历元到达后最早8.01s锁定；3s/5s Arm不要求UTC LOCKED，但其模式所需导航/measurement time/PreArm必须真实有效，不能等待PPS锁定阻塞IMU，也不能在3s伪报已锁定。STATIC_ALIGN所需静止先验及GNSS初始化资格仍按来源门控。

高层ScenarioDriver只提交请求并观察公开ACK/任务状态来生成后续合法请求，不写Chart内部状态；Mission的期望epoch取此前公开提交结果，负向旧epoch记录原样保留，不在消费者处改成当前值。

参考位置/速度连续，M5产生实际消费Hermite曲线；场景文件只给高层意图，不直接给电机。依赖输入不满足时不得强行让场景脚本把FMS状态改为ARMED。

## 6. 典型故障变体

RC loss 12..14s且无takeover；RC恢复后回中；17s明确接管；Baro bias阶跃；磁干扰；IMU丢1/2条、重复/倒序；辅助延迟19/20/21ms；旧Permit/Reference重放；MPC迟到/不可行；Frame tick丢失。每个变体独立manifest、预期策略和退出原因，不无界随机叠加。

GNSS故障分成独立场景：GNSS_PVT_OUTAGE_10_20、PPS_OUTAGE_10_20、GNSS_PVT_PPS_OUTAGE_10_20、UTC_EPOCH_INVALID以及已安装但冷启动无Fix。半开失锁窗口[10,20)s内前者仅停止PVT/置NO_FIX、保持经证据确认的PPS/历元；第二个仅停止PPS；第三个同时停止PVT/PPS并声明历元是否有效。模拟真实接收机失锁时PPS质量若也不可靠须明确拒绝，不能默认其继续有效。需要证明恢复与重新锁定的场景StopTime=35s、20s恢复输入，最早28.01s才完成8个新PPS间隔及历元配对；不冒用名义30s任务成功指标。各stream保留失锁gap及完整coverage，非意外EOF。

ExtINS导入还须声明source_aiding_outages及状态/协方差来源。要检验GNSS丢失必须离线重跑参考器并移除对应PVT更新，再捕获完整Nav/P；不能只给持续有效的外部Nav贴GNSS_LOST标签。没有PPS/历元记录的历史数据只证明导航/控制回放，外部授时部分标NOT_COVERED，不补造锁定事件。

记录数据不能按新控制输出推进物理状态。DataSIM与ExtINS_DataSIM只有counterfactual控制审计，M7 Receipt为虚拟提交，report.physics_closed_loop=false；MIL为true。切换此字段不能代替实际拓扑核验。

## 7. 输出

统一Simulink.SimulationOutput/logsout：SimTimeline/FcuClock/RunBinding、TimeServiceStatus/LocalTimebaseDisciplineStatus、独立GNSS PVT/PPS/历元质量及计数、nav/capability、fms_state、directive/permit、reference/guidance、control/capability/solver、actuator_frame/receipt、fault/decision、truth（MIL单独域）。report包含run/源码/模型/CORE/数据Hash、起止时间、模式、metrics、异常和结果；大记录可用MAT分片，无需GUI。

比较旧Control_Out或旧INS只作标明单位/时序的诊断；不能把旧模型同名输出当新的唯一黄金。缺失golden时保持NOT_RUN。

实施顺序要求G2先提供解析静止/已知运动的SYNTH_1KHZ_OPEN_LOOP数据集作为两类回放的首个合格输入；不等MIL闭环完成才开始回放开发。G7产生的MIL记录是后续回归输入，不是G6前置。
