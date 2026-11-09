# FlightSIM Simulink控制链设计

状态：设计草案；2026-11-05。数学和资源选择继承[父控制04](../../Flight/spec/04_飞控核心模块与控制系统设计.md)，本文件确定建模分解，不能以名称相同的旧MC Controller替代。

## 1. 可见的Simulink层次

```text
FMT_M6_Control
  InputContractGuard
  ReferenceSampler
  TranslationalControl
    MPC_StatePrediction / QPAssembly / OSQP_QPSolver / QPValidation
    PD_Backup
    MpcSnapshotGuard
  ThrustAndAttitudeTarget
  SO3_AttitudeError
  RatePID
    MeasurementDerivativeLPF / P / IntegralState / BackCalculation
  X4_ControlAllocation
  CommandHistoryAndReceipt
  OutputContractStamp
```

原生矩阵/Sum/Gain/Unit Delay/Saturation/Switch等块实现信号流和状态。3×3 Log、固定矩阵分解等有限数值内核可用MATLAB Function；QP求解器是独立C接口。禁止一个Interpreted MATLAB Function调用全部controller_step，禁止在Stateflow during动作里运行PID/MPC。

## 2. NumericTransaction与ContextEvaluation

按[执行协议第3节](FlightSIM-execution-protocol.md#3-m6读取评价提交)统一采用Read S[k]→Evaluate→Allocate→Validate→Commit S[k+1]，取代先StateAdvance更新积分、再计算同次输出的方案。批量Nav逐条完成真实事务，本tick只发布最后一份Demand。全局已消费State Time水位与可重置的I/D历史分开。

同Nav的新授权、Nav修订或新MPC结果只做ContextEvaluation，不增加dt/jerk额度；新context做一次I=0、D/前馈=0的ResetTransaction后可立即用仍新鲜的Nav评价，不能因没有新Nav把旧token送Frame。验证失败不提交数值历史；新约束不可行则拒绝，不宣称任意切换无扰。

Control Time=所选Nav State Time，evaluation_time=FcuClock；参考按独立的、非未来grid anchor插值。MPC仍20ms最多一Job，CG[p,v]、NED运动加速度、Ts.02、Np20/Nc5/保持u4。所有公共字段与算法内部分支严格区分。

## 3. MPC求解器与失败定义

QP固定15变量/190约束行，状态盒120、输入盒15、输入差分15、倾角面40；静态稀疏模式。采用OSQP v1.0.0，Git tag指向236713ce9a56c182ac3230d52108f952afce1523，导入时核验整个依赖树/Hash。mode2支持P/A数值更新；mode1不够。Host生成MEX/S-function仅包求解器；QP构造、约束验证和缓存守卫在可见模型内。

最大80迭代、绝对/相对容差1e-3；Job默认虚拟cost1000us、deadline2000us，结果到ceil((start+cost)/500)*500才对快环可见；SOLVED_INACCURATE仍需primal/dual residual及独立最大违反量≤1e-3。原生状态显式归一化为父ICD solver_status。禁止用quadprog/mpc控制器块悄悄替代OSQP结果作为最终交付。

若MEX依赖或编译器不可用，模型只能进入PD_BASELINE开发阶段并标明MPC_UNAVAILABLE；最终验收必须运行真实MPC且满足T-CTL-02分别定义的job成功率与时间覆盖率，不能全程fallback仍宣布完成。

输入/推力/倾角约束按父04保守域，预检Tmin/m≤g≤Tmax/(sqrt(3)*m)。u_prev_command取最近一次约束后接纳的加速度；不是Plant实测加速度。共享输入差分jerk盒，快环按实际dt再检查一次，不能直接把20ms求解间隔用作1ms快环限速。

MpcOutputSnapshot含种子p/v、State Time、求解开始evaluation、完整epochs、source_deadline与expires。导航5ms TTL仅在求解入口检查；快环用新Nav和种子预测残差/25ms种子界检查。授权/参考/模型原截止、20ms窗口取最早；不因续租无限延长旧解。具体公式只维护在父04。

## 4. 推力与SO(3)

g_n=[0,0,g]；T=m*norm(g_n-a_d)，b3d=(g_n-a_d)/norm。航向North向East为正；退化叉积投影上一有效轴，仍退化时用确定备用轴并报DEGRADED。

E=R_nb' * R_d，e_R=vee(Log(E))；ω_sp=E*ω_d+K_R*e_R。Log必须覆盖微角与π，不能把sin(theta)反对称近似当完整Log。期望角速度离散差分、零/π阈值和q/-q等价按父04。Host按G0-HOST选定的N0/rate核验，固件等价另经FirmwareConformanceGate，不能在同一误差中混用ω_ib与固定N0相对rate。

## 5. Rate PID与分配

每轴e=omega_sp-omega_meas，D只对测量差分低通。tau_req[k]=Kp*e+I[k]-Kd*D_candidate；当前分配残差r[k]=tau_alloc_est[k]-tau_req[k]，I[k+1]=clip(I[k]+Ki*e*dt+Kaw*r[k]*dt, +/-I_limit)。I[k+1]只在本次全部检查通过后写下一状态，不反馈到本次tau_req；取消额外旧残差延迟。首帧/新context导数与前馈为0，重复评价不积分。增益为Nm物理单位，不沿用旧归一化值。

分配矩阵按旋翼相对CG的位置、FRD向下推力反向和gamma生成：T=sum f，τx=-sum(y_i*f_i)，τy=sum(x_i*f_i)，τz=sum(gamma_i*f_i)。优先保持roll/pitch，再总推力，再yaw；用有界区间求交/比例缩放，不逐电机独立clamp伪装可行。饱和/秩不足更新能力与原因。

M6输出四路N。首版附加Receipt抗饱和增益固定0，只保留8项命令历史、匹配诊断；主路径为allocator残差，防止重复叠加旧Receipt和旧请求产生双重反馈。ESC_FEEDBACK_CAPABILITY=NONE，不借Plant实际推力闭合anti-windup。输出整链见第8节。

## 6. 模式和备用

| 模式 | 参考和控制 |
|---|---|
| MANUAL_RATE | 授权Pilot RATE+throttle，Rate PID与分配 |
| MANUAL_ATTITUDE | 授权q/航向rate+throttle，SO(3)+Rate PID |
| 人工ALT_HOLD | ALTITUDE_PILOT=4及ALTITUDE_ATTITUDE载荷；垂向PD与人工姿态，T=m(g-a_D)/R_d33 |
| POS_HOLD/任务/RETURN | 完整轨迹；MPC或同约束PD备用 |
| LAND/EMERGENCY_LAND | 完整位置用MotionReference；Directive LAND/ALT_HOLD只接纳ALTITUDE_AUTOMATIC=5及ALTITUDE_ATTITUDE载荷，垂向PD→给定姿态→Rate/分配，不进入XYZ MPC |

自动垂向分支不要求Pilot Authority/摇杆，仍须完整匹配M4活动上下文/Permit及垂向位置/速度、姿态/角速度能力，execution_token=0。缺水平值不参与数值运算；参考kind未知或与Directive/GuidanceStatus不配对立即拒绝。垂向PD与人工ALT使用同一有限内核和T公式，R_d33必须为正且满足当前倾角包线，再检查总推力界；不靠除零后clamp获得结果。M6不能自己选择该降落分支或改变FMS。

无导航能力或无可行约束时不发布有效Demand。QP失败最多在原TTL内保持一个20ms周期，再使用已定义PD；PD同样不能满足约束则交M4策略，不隐藏错误。

## 7. SIM_ONLY整定种子

下面只是固定合成fixture初值，待MIL整定后按revision更新；不代表实机适用。

| 量 | 初值 |
|---|---|
| SO3 K_R | [4,4,2] s^-1 |
| Rate Kp / Ki / Kd | [.16,.16,.12] / [.08,.08,.04] / [.002,.002,.001]，单位见父ICD |
| Kaw / D滤波 / I上限 | [5,5,5] s^-1 / 30Hz / [.08,.08,.05] Nm |
| PD kp / kd | [1.5,1.5,1.5] s^-2 / [2,2,2] s^-1 |
| Q / R / S / Qf | diag[8,8,12,3,3,4] / diag[.8,.8,1] / diag[.2,.2,.25] / Q |
| max tilt / body rate | 25deg / [2,2,1] rad/s |
| seed误差限 | 位置0.5m、速度0.5m/s；改动须记录数据与误拒情况 |

控制调参来自四份CORE，结构/安全种子来自readonly Profile生成结果，不能同时在块Mask与workspace保存独立副本。最终参数是否合格由测试判定，不在本轮预填PASS。

## 8. M7量化与物理应用的唯一链

Demand(N)→当前范围/基于上次已提交N的frame slew区间→可行整数code集合→最近code→checksum packet→pending frame→固定500us后应用→Plant motor。Receipt.committed_demand必须由所选整数code逆映射，Plant也读取该值，不能一边验code一边把原始未量化Demand直接送Plant。

SIM_ONLY种子每电机两点曲线(0N,48)、(10N,2047)，0N停机单独编码0，1..47不作油门；曲线严格单调，未用表项清零。正推力先得实数code再取最近整数，平局取小code；以floor/ceil构造满足物理范围/slew的整数区间后再选，不能round后越界。max_slew=100N/s，每2.5ms允许0.25N变化；量化物理分辨率10/1999N。初始上次提交N=0，IDLE_ONLY由M7 poll产生合成0.2N/电机并同样限slew，不调用M6闭环。manual_hover_throttle_norm=.5、Tmin=0N、Tmax=40N、jerk_max=[5,5,5]m/s³、加速度上限[2,2,2]m/s²、速度上限[2,2,2]m/s均入SIM_ONLY配置。

初始抑制不要求Demand；普通地面Disarm在DISARMING由M7凭GroundStopCertificate按整数slew逐帧降至0，零目标应用后才DISARMED，默认含应用延迟最坏105.5ms到零目标，随后只有电机物理衰减。该事件不属于运动Demand/命令Receipt，不能作为空中失效的通用零输出策略。

虚拟协议固定DShot600、telemetry request=0；按标准16bit packet组成checksum，18bit占用的虚拟end=start+30us。这里只模拟编码/有界完成事件；不生成TIM/DMA波形，不声称已验证真实ESC。apply=start+500us是合成固定延迟，大于packet end，写入manifest；Receipt在下一个release tick可见。撤销阻止新帧，已开始帧保持其真实提交事实，不倒改历史。Frame节拍2.5ms与600kbps独立。
