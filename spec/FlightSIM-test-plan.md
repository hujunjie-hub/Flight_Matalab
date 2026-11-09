# FlightSIM 验证计划与当前台账

状态：系统级目标/扩展故障矩阵文档，包含当前尚未全部实现的目标项。当前分支实际可执行的测试数据集、验收命令、报告与状态以 [MATLAB 仿真测试数据集与验收标准](MATLAB-验收与结果提交.md) 为准。T-SPEC-01..04 的静态/来源/算术/规格参考 PASS 不表示任何 `.slx` 已编译或仿真。

## 1. 验收层级和运行矩阵

顺序为配置/接口→组件MIL→算法集成开环→Plant开环→系统MIL→故障/鲁棒→后续SIL/PIL。三个入口各冷启动compile+2s smoke，再各30s完整输入；原生KF21数据集单独按原频率运行，不混入1kHz控制达标率。StopTime必须有限。

| 入口/数据 | 必做 | 能报告的结果 |
|---|---|---|
| FMT_DataSIM / SYNTH_1KHZ_OPEN_LOOP | 原始/M2标准路径分别重放；正常和坏manifest | 导航/控制契约与反事实输出，不报告物理闭环RMS |
| FMT_ExtINS_DataSIM / CONTROL_QUALIFIED捕获 | Pristine21 full-state MAT及完整Nav bundle | 外部导航适配和反事实控制；缺字段应拒绝 |
| FMT_MILSIM / 30s默认SIMULATION | 全部物理/源/控制链及高层请求 | 唯一闭环跟踪/任务/着陆指标 |
| KF21_REFERENCE_ONLY / 原生数据 | 原始频率、配置、truth/STD比较 | 原生算法复现，无运动Permit |
| NONE / 裁减回归 | 不要求避障任务通过；要求避障任务拒绝 | 几何项NOT_APPLICABLE，不能报告碰撞PASS |

所有结果保存Profile、源码/模型/参数/schema/data Hash、工具版本、seed、相位、输入、评价窗口、期望/实际、日志及稳定reason code。状态仅NOT_RUN/IN_PROGRESS/PASS/FAIL/WAIVED，当前没有豁免。负向用例只有命中预先声明原因、时间窗且未产生非法帧才PASS，意外SimStop/提前结束为FAIL。

## 2. 结构、构建和接口

| ID | 场景 | 接纳条件 |
|---|---|---|
| T-SYS-01 | 三入口分别冷启动 | 新MATLAB进程仅开新项目，compile+2s及30s完整输入；不依赖原工程path或残留base变量 |
| T-SYS-02 | 30s物理名义任务 | 第7节指标全部满足，Land/Disarm在30s前完成，并运行M7地面stop后的自然电机衰减 |
| T-SYS-03 | 故障矩阵 | 第8节逐项命中期望动作和deadline，无事后改expected_outcome |
| T-BLD-01 | 工程开关/外部依赖 | startup两次无重复path，shutdown恢复；重复同名实现、缺依赖或Hash错在compile前失败 |
| T-BLD-02 | 四CORE+Profile生成 | 重复生成内容Hash一致；缺字段/重复键/NaN/错单位/隐藏第二份参数拒绝；生成视图与源Hash绑定 |
| T-BLD-03 | OSQP构建缓存 | 版本/精度/稀疏模式/编译器/MATLAB架构改变即缓存失效；无有效MEX不准最终验收 |
| T-ARCH-01 | 共享实现/依赖图 | 三入口同一M4/M5/M6/M7；M3恰好一个活动源，非活动Variant无发布 |
| T-ARCH-02 | truth隔离 | 动态truth只到SensorFrontend/Evaluator；初始化是Scenario先验，不能运行中读truth |
| T-ICD-01 | typed bus/schema | 字段/类型/尺寸/公共名与选定上位快照一致，未知enum/bit拒绝；不把bus视作C内存镜像 |
| T-ICD-02 | 坐标/重力/q | 正负号、deg/rad、Up/Down、q/-q分别验证 |
| T-ICD-03 | 非零IMU/CG/天线杆臂 | 理想旋转p/v/STD解析一致，安装旋转和杆臂不重复补偿 |
| T-ICD-04 | age/sequence/valid mask | Nav/Capability跨世代混搭、未来时间、缺方差拒绝；sequence半范围而非epoch回绕 |
| T-ICD-05 | stop/init/reset | 初始/解锁前缺Demand正常抑制，普通地面stop与空中SimStop分开；局部重建保留高水位，先抑制后stop；新boot才清旧上下文，source reset不无故重启全图 |
| T-GEO-01 | N0与当前LLH-NED | 点ECEF往返≤1e-7m、向量旋转误差≤1e-12相对；位置平移不作用到v，q/rate/covariance采用同一完整变换 |

## 3. Stateflow/权限

| ID | 场景 | 接纳条件 |
|---|---|---|
| T-FMS-01 | 五域初值/合法组合 | default唯一；非法组合不可提交，Chart与公开状态一致 |
| T-FMS-02 | 首次Arm | READY→匹配Permit→ACTIVE，绝对100ms超时撤销；IDLE_ONLY每次≤25ms |
| T-FMS-03 | 旧Permit/乱序续租/撤销 | watermarked旧授权无法重装，下一新帧无旧token，已开始帧事实不回写 |
| T-FMS-04 | RC loss/recovery/takeover | lost300ms、恢复500ms；回中不接管，显式接管换epoch/暂停任务 |
| T-FMS-05 | 两航点/暂停/恢复/中止 | M4唯一推进；正式MISSION_EPOCH bit8、非零当前epoch；旧/缺epoch/旧token不推进 |
| T-FMS-06 | Home/水平能力/能源缺失 | 依赖RETURN拒绝；普通POS_HOLD不无故要求Home；自动垂向着陆需M4明确kind5且无待证明围栏，默认围栏不自动关闭；缺垂向能力也拒绝 |
| T-FMS-07 | 接地/空中Disarm | CONTACT+有效v/a及2s dwell才普通Disarm；缺项UNKNOWN |
| T-FMS-08 | TERMINAL维护清除 | 地面/DISARMED/明确请求/健康齐全；恢复不自动清锁存或恢复任务 |
| T-FMS-09 | 初始化与probation | M2事实可独立建立初始化，配置先验100ms或静态对准2.5s内Nav就绪；无heading仍未建立，恢复不偷走初始化捷径 |
| T-FMS-10 | 同tick安全/Arm/接管/模式请求 | 一次事务按优先级决定；五域/epochs/ACK一致，无重复副作用 |
| T-FMS-11 | 队列/cache/长操作耗尽 | 4请求/4长操作/32幂等记录边界准确；异payload同键拒绝，60s内不逐出活动请求 |
| T-FMS-12 | 普通热切换/取消/抢占 | PREPARE期间活动bundle不裂开；READY下一事务完整COMMIT；80ms超时不复用保留epoch/token，硬撤销立即生效 |

G4导出唯一TransitionCatalog（Chart state/transition ID、触发条件和预期domain tuple）；每个设计可达迁移至少一次，覆盖率100%。不可达项须回到设计删除或给出不变量证明，不能只报一个总覆盖百分比掩盖缺模式。没有Coverage工具箱可用转移ID日志实现同一检查。TransitionCoordinator的PREPARE/ABORT/COMMIT及DISARMING管理停止状态也在目录内。

## 4. 制导

| ID | 场景 | 接纳条件 |
|---|---|---|
| T-GDN-01 | 七层与完整输入 | map/fence/Home/人工kind/任务token显式接入；缺必需成员拒绝 |
| T-GDN-02 | NONE与SIMULATION | NONE不造全FREE；SIM没有更新500ms后STALE；源失败不自动换NONE |
| T-GDN-03 | A*根/时间键/容量 | 交接参考根不吸网格，WAIT不合并旧time_bin；512节点/扩展、3前缀+5新段、time_bin≤30/6.0s及准备80ms边界明确失败 |
| T-GDN-04 | 连续曲线/碰撞/围栏 | 点间窄障碍、动态穿越和未知尾窗均拒绝；深度5/总256单元耗尽不作成功 |
| T-GDN-05 | 候选与活动槽 | 旧revision/Origin/token拒绝；首保持可READY，规划未完成不发新任务Permit |
| T-GDN-06 | 人工/自动ALT typed参考 | RATE/ATTITUDE/ALTITUDE_ATTITUDE的mask/单位正确；人工yaw按State Time积分，三点throttle在hover连续；自动kind5每段≤1m且v/a连续、Home/LANDED截断，重复预览不推进 |
| T-GDN-07 | 静止首边/细分retimer | 默认a2/j5旧0.4s反例应拒绝，新边固定终点、深度4导数界与0.2s整数T通过；真实T计入time_bin/g |
| T-GDN-08 | 精确目标/搜索启用 | 非格点目标用GoalConnector；强制A*自由空间和至少一个障碍Profile成功，含connector新路径≤5段 |
| T-GDN-09 | 准备预览/yaw/ALT副作用 | 同输入预览20次，活动状态不变；激活/后续State Time只提交一次，ALT按父02公式 |
| T-MAP-01 | 世界调查/动态对象 | 4096 cell及coverage完整校验才安装；空对象列表不造FREE，部分调查UNKNOWN，私有source不冒传感器实例 |

## 5. 控制和估计

| ID | 场景 | 接纳条件 |
|---|---|---|
| T-CTL-01 | 双积分器/Hermite | p/v/a端点及C2连续；double内核归一化误差≤1e-9；公开single按1e-7绝对+1e-6相对 |
| T-CTL-02 | OSQP与名义占用 | 15变量/190行、独立residual/违反量≤1e-3；有效名义求解job成功率≥99%，时间加权MPC覆盖率≥90%，分别统计 |
| T-CTL-03 | infeasible/max_iter/late/NaN | 到原expires即拒绝旧解；同约束PD或预期安全终止，无延寿 |
| T-CTL-04 | 饱和/AW/释放 | I≤限值，本次请求/分配残差只写下一I；阶跃释放后2s内回到T-CTL-06误差带，不叠加Receipt双重AW |
| T-CTL-05 | SO3微角/π/±179.9/180.1deg | Exp(Log(R)) Frobenius误差≤1e-6，所有结果有限，q符号等价 |
| T-CTL-06 | 0.5rad/s rate阶跃 | 无地面/无饱和影响的独立MIL fixture，1.5s内进±5%、超调≤30%，保持2s |
| T-CTL-07 | 模式切换/仅垂向能力 | I/D重置与参考连续性符合规定；无Pilot输入的授权kind5可走垂向链且token0、不读无效XY；错kind/非零任务token/错Directive拒绝；执行推力变化≤frame slew |
| T-CTL-08 | Receipt/历史匹配 | 8项历史按sequence匹配，过旧忽略；只作命令证据，首版附加AW增益0 |
| T-CTL-09 | code闭环 | Plant/Receipt用code逆映射N；code0或48..2047，checksum正确，slew≤100N/s，提交到应用500us |
| T-CTL-10 | 数值提交顺序/失败原子性 | tau用I[k]，当前r写I[k+1]；首帧仅seed，不猜dt；同Nav复核/失败不多提交I/D |
| T-CTL-11 | 地面stop事务 | 仅DISARMING且证书有效，slew/整数码合格；≤105.5ms零目标应用后才DISARMED，不冒称实测RPM |
| T-INS-01 | 原生21重复 | 同工具/源/配置/输入double归一化误差≤1e-12；完整捕获Launcher终态full state/P与未修改driver退出前捕获量一致，全序列文本按各列格式量化区间比较 |
| T-INS-02 | Project22核心对比 | 关闭新增/已知不等价项、统一初始化/观测边界：p≤1e-5m、v≤1e-6m/s、姿态≤1e-7rad，P≤1e-8+1e-6*abs(P_ref) |
| T-INS-03 | H/Phi/Q/Baro bias | 按同error retraction中心差分，归一化列误差≤1e-7+1e-5*abs(J_ref)，交叉P不清零，有限且可分解 |
| T-INS-04 | replay竞争/边界 | Shadow最多4单元/tick/8待接纳容量准确；与相同门控/端点量化/排序的有序基线在T-INS-02门限内；旧revision不提交，不用未量化理想基线误判 |
| T-INS-05 | 辅助中断/恢复 | covariance/能力退化、probation窗口真实满足，不自动恢复任务 |
| T-INS-06 | IMU gap/非uniform/标定变化 | 不复制样本，gap/策略/版本明示；坏候选不污染活动状态 |
| T-INS-07 | 初始化/CG发布 | gravity不提供yaw，STD来自完整变换P；缺端点rate/full P的外部文本REFERENCE_ONLY |
| T-INS-08 | P0/Qc/GM/RW及旧快照 | 初始STD与平稳STD/PSD分开，Qc19顺序/单位准确；失败不刷新旧Nav时间；NIS使用明示真值噪声Profile |

MPC覆盖率分母是预先选定的自动平动、输入/授权/约束有效时间，按500us区间加权；初始化和显式人工/垂向模式不计，模式进入后只允许固定前100ms warmup，每次排除量单列，不按失败结果追加排除。至少100个合格job。start+20ms expires与下一20ms job间天然有cost空窗：默认1ms时理论95%，2ms时90%；该空窗使用PD并照常计入闭环RMS，不能通过把旧解延寿来满足覆盖率。求解成功率和覆盖率两项任一失败均FAIL。

## 6. 时间、数据和数值比较

| ID | 场景 | 接纳条件 |
|---|---|---|
| T-TIME-01 | 60s节拍 | 半开区间[0,60s)：基步120000、IMU物理采样60000、frame_due24000、FMS周期6000、Guidance/MPC槽3000、GNSS PVT600/PPS60/历元60；released/传播/数值提交/有效帧另按边界守恒计数；事件提前执行另计，不重复周期槽 |
| T-TIME-02 | sample/capture/arrival/release | IMU0→2000→2300→2500us首条因果链；STANDARD不重复扣pipeline，额外200us等待单列 |
| T-TIME-03 | TTL/age边界 | 门限前1us/等值/后1us与tick释放分别验；expires等值拒绝，age上限按父边界，无uint64下溢 |
| T-TIME-04 | boot/time/source reset | 局部stop/init保留高水位，source reset只失效依赖，全图重启换boot |
| T-TIME-05 | 辅助19/20/21ms、60ms job | 入队age/deadline分别判定；只有左右端点可见才量化，不跨gap |
| T-TIME-06 | 乱序/同刻/超cap | 唯一事件键与count相同，未处理超预算有gap；4条IMU推进不伪称四个实际Frame |
| T-TIME-07 | MPC可见性/逾期 | 虚拟cost0.5/1/2/2.001ms；available前不可读，过2ms拒绝，Host墙钟不替代虚拟deadline |
| T-TIME-08 | 同Nav授权切换 | 在FMS和Frame同刻且无新Nav条件下，ContextEvaluation使用新上下文；I/D更新次数不增加，旧token不提交 |
| T-TIME-09 | 双时间轴/跨boot迟到 | FCU local归0时global继续；旧boot先拒绝再算age，源事件/Plant/StopTime不重置 |
| T-TIME-10 | 固定grid/前缀交接 | jitter State Time不移动家族grid；prefix逐点相同、p/v/a C2、yaw C1；迟于activation_deadline拒绝 |
| T-TIME-11 | 完整边界记账 | 生成、release、propagation、NumericCommit、frame_due各自守恒；30s默认IMU生成30000、理想release29997不能混称 |
| T-DATA-01 | 坏manifest/单位/级别 | 导入前拒绝；RAW_ENGINEERING、RAW_CAPTURE、STANDARD分别覆盖，不能互冒解码验收 |
| T-DATA-02 | ms时间/缺P/端点rate/arrival | 按限制REFERENCE_ONLY或拒绝，不补零方差/假时间；历史授权只进评价 |
| T-DATA-03 | 重复seed/新run | 归一化语义投影一致；boot/run_id必须不同且完整保留，不用公共头memcmp判可重复性 |
| T-DATA-04 | 开闭环报告/EOF | 回放physics_closed_loop=false；t_stop只记终态、无新命令，每stream按coverage/计划/Hash/计数判EOF，合法pending tail和低频最后记录不误报 |
| T-DATA-05 | RunBinding/合法结束 | 测量/Nav重绑定保持原Header provenance和质量；授权不重盖头，低频EOF/tail/gap覆盖按协议 |
| T-DATA-06 | 35s/重启能源fixture | provider覆盖整个RunInterval，t_sim不因FCU重启归0；35s值.865、TTL有效 |

数值比较先统一单位/frame/参考点/时刻。q先归一化，q_rel=conj(q_ref)⊗q，姿态角=2*atan2(norm(q_rel.xyz),abs(q_rel.w))，替代近零不稳定的acos(dot)。有限差分步长按状态列尺度取1e-5倍，减半/加倍两次误差均须满足界；接近零项使用绝对项，不除0。

重复性投影仅去掉run_id/boot_id、文件绝对路径和墙钟，FCU local按各boot/time段RunBinding还原到Simulation Time；保留相对时间、sequence、全部epoch、状态、reason和数值。same release/CPU/solver下，single atol1e-7+rtol1e-6、double atol/rtol1e-12；跨版本对比单独报告，不冒同运行确定性。

## 7. 物理名义窗口

[7,10)s悬停位置RMS=sqrt(mean(||p_truth(t)-p_reference(t)||²))≤0.25m，姿态角RMS≤3deg；truth与所执行参考经RunBinding按同一global物理t查询，不能把当前truth与旧State Time参考混比。采样覆盖100%，不能删除无效点后只报好区间。原始估计误差另以Nav State Time查询truth，不混为控制跟踪误差。任务按token完成、23s发Land、30s前可靠LANDED/Disarm；没有足够落地dwell则FAIL。

## 8. 故障判据

| 故障组 | 必须前置/预期 |
|---|---|
| RC loss/recovery/接管 | 既有任务/能力有效；300ms lost后下次M4事务执行策略；恢复500ms只恢复链路，显式边沿才接管 |
| GNSS PVT/PPS/历元丢失 | 固定器件仍启用，三路质量/覆盖分开；先源/时间证据、再能力与FMS动作；按T-GNSS-01..06执行，不以大残差直接定因 |
| Baro/Mag drop/bias | 逐源独立manifest；先源/观测证据、再能力与FMS动作 |
| IMU gap/共因时间异常 | M2/M3门控先行；无可信姿态时无新控制帧，预期SimStop窗口≤下一500us区间开始 |
| QP late/infeasible | 有合法PD前置时继续并计RMS；无约束可行解则指定拒绝/SimStop，不能统一要求返航 |
| Frame丢失/许可过期/旧token | 新帧在当前水位/TTL复核；已发帧事实保持，非法新帧数=0 |
| 电机物理退化/外力 | 通过测量/跟踪证据反映；不得把Plant故障真值直接设为健康标签 |

fault_manifest在执行前固定start/end、initial mode/capability、预期reason集合、最晚动作时间和预期结束状态。运行器不能从实际错误中自动生成期望。安全停止场景不报告“已安全着陆”。

### 8.1 固定GNSS/PPS与中途失锁（全部NOT_RUN）

| ID | 场景 | 接纳条件 |
|---|---|---|
| T-GNSS-01 | 固定产品/名义30s | Manifest的GNSS/PPS installed/enabled四个位全true；任一false/缺项在生成前拒绝；PVT10Hz/PPS1Hz/历元配对独立存在，不能采用已废止的默认关闭配置或以模拟数据冒充UART parser验收 |
| T-GNSS-02 | 已安装、冷启动无Fix/未锁定 | 设备保持存在且已启用；local clock/IMU持续，不报NOT_INSTALLED；可由明确prior建有限Nav，首次合格GNSS资格/稳定窗前不给自动位置能力；无合格历元utc_valid=0，首8个PPS间隔和历元到达前不得LOCKED；名义最早8.01s |
| T-GNSS-03 | [10,20)s仅GNSS PVT停包或NO_FIX | 同一Profile，PPS/历元由独立有效证据保持；NO_FIX不融合，停包≤400.5ms确认GNSS_NAV_LOST；不重复旧PVT、不伪造速度/清P，不自动使时间LOCKED丢失；M4动作按实际能力，位置返航不得绕过能力门槛 |
| T-GNSS-04 | [10,20)s仅PPS停包 | PVT继续且按自身时间质量接纳；末次合格沿在9s，11.5s到期后最多500us报PPS_LOST/进入有据HOLDOVER或误差越界后的DEGRADED；local clock/IMU和boot/time_epoch连续，不能把PPS丢失当设备移除 |
| T-GNSS-05 | PVT/PPS同时失锁、或UTC历元明确无效 | 分别记录GNSS_NAV_LOST/PPS_LOST/UTC_EPOCH_INVALID；明确无效历元立即清utc_valid，不凭PPS生成绝对时间；需要映射但误差不可证明的PVT拒绝；源故障不能冒充TIME_BASE_FAULT，原围栏继续生效 |
| T-GNSS-06 | PVT/PPS同时失锁后20s恢复至35s；回放/ExtINS同义 | GNSS先probation再能力进入dwell，PPS从20s新序列累积8个间隔且配对到达后最早28.01s重新锁定；单独在15s经合法请求将任务PAUSED，恢复后保持PAUSED直到显式有效RESUME；无时钟跳变/伪新Nav，ExtINS须重跑参考器的失锁输入并捕获新Nav/P |

所有失锁场景使用declared gap而非EOF或删除源模型。目标动作与期限由事先声明的能力/模式/时间误差条件判定；不能要求任意GNSS丢失都立即返航，也不能宣称惯导可无限维持位置。历史数据缺PPS/历元仅标授时NOT_COVERED，不计这些用例PASS。

## 9. 已执行检查范围

| ID | scope | 证据 |
|---|---|---|
| T-SPEC-01 | DOCUMENT_STATIC | validation/spec_review_report.json；结构、链接/锚点、需求/测试引用、全部历史及本次三轮问题处置 |
| T-SPEC-02 | SOURCE_READ_ONLY | validation/source_integrity_report.json；原工程完整Hash、上位精确快照及已审增量 |
| T-SPEC-03 | ANALYTIC_DESIGN | validation/design_arithmetic_report.json；节拍、MPC覆盖率上界、悬停/接触、量化边界；不是模型运行 |
| T-SPEC-04 | EXECUTABLE_SPEC_REFERENCE | validation/semantic_reference_report.json；13个反例/协议参考与192组独立多项式界，非模型执行 |

检查器失败也必须写FAIL替换旧PASS，退出码非0；结果带当前输入Hash，不能沿用旧报告。规格完成不自动开始模型改造。
