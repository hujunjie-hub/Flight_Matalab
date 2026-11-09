# 实施状态

当前交付范围为 **Flight 固件 Windows Host SIL**。现行合同为 Schema 6.0、Product/Port `0x00010906`。三个顶层模型和共享飞控模型已生成并注册到 MATLAB Project。下表是此前记录的 Host SIL 基线证据；本轮更新了 MIL 传感器事件队列、参数预检和测试脚本，当前分支尚未在 MATLAB/Simulink 重新执行完整验证，相关 manifest 已标记为 STALE_REQUIRES_RERUN。

| 范围 | 实测结果 |
| --- | --- |
| Flight 固件基线 | 上游 Host SIL 通过 3,151 项检查，配置及源码共 457 个文件完成 SHA-256 核对 |
| 公共类型 | 重新从现行固件头文件生成 106 个值类型 Bus |
| MILSIM | 26 s 闭环，完成解锁、2 m 起飞、降落、上锁；实际最高 1.986 m，最终速度接近零 |
| DataSIM | 回放 MIL 标准工程量传感器与指令，诊断和四路提交推力逐样本一致 |
| ExtINS DataSIM | 在 M3 输出边界回放保存的导航快照和能力，飞行状态和四路提交推力逐样本一致 |
| 冷启动 | 独立 MATLAB 进程中，三个入口的默认输入冒烟和完整复跑均通过；MATLAB Project 9 项检查通过 |
| 缺测保护 | DataSIM 全传感器缺测时，解锁指令产生的提交推力持续为零 |

`implementation_manifest.json` 记录模型、录制数据、源码和仿真证据的完整性信息。单点接地在上锁后会倾倒，最终 SIM_ONLY 物理对象采用四点接地与正则化摩擦。ExtINS 的默认录制来源为 MIL 中的固件 KF-GINS。当前证据覆盖主机仿真与合成输入，STM32 时序、HIL 链路、实体执行器和实飞另行验证。



## Plant 物理模型第二阶段（代码状态）

以下是独立的 Plant 算法验证代码状态，不计入上表已实测通过的 Host SIL 结果。当前尚未在 MATLAB/Simulink 环境运行本阶段测试。

- Plant 参数合同扩展为 26 项：质量、完整 J(:) 3×3 惯量、k_f、电机时间常数、阻力、角阻尼、地面接触、重力和摩擦系数。
- 刚体角运动使用完整 J·omega、omega×(J·omega) 和 Cholesky 求解 J*alpha=rhs；参数入口拒绝非对称或非正定惯量。
- Plant S-Function 对状态、环境、wrench、参数和输出做有限值检查；ground/drag 开关严格为 0/1，rotor_effectiveness 限定 [0,1]。
- 第一版地面摩擦系数明确设为 0；增加静态 mg/k 支撑、无水平摩擦、FRD/NED 变换、风阻、250 μs 独立 RK4 参考和输入拒绝测试。
- 传感器参数合同增加 SensorModelParameters（54 项），包括 IMU/MAG 安装矩阵、gyro/accel/mag 残余 bias/scale、IMU/MAG/GNSS/Baro 噪声 STD 和固定随机种子；随机数由 seed/source/sample-index/axis 无状态派生，不随 RK4 子步或调用顺序变化。SensorTimingParameters（10 项）已接入 MIL Host SIL 独立事件队列：IMU/GNSS/MAG/Baro 分别按配置周期采样，保留 sample/capture/arrival/release 四个时间，区分物理到达和 500 μs 队列实际交付时刻；队列统计 generated/suppressed/released/accepted，并验证缺测导致的序号缺口、计数守恒、队列容量和固件样本有效期。
- 当前代码覆盖 P-01～P-09、P-11～P-13、P-15～P-21；P-07/P-08 覆盖杆臂运动学和静止 IMU，P-09 已加入相同 seed 重复性、不同 seed 独立性、IMU 噪声 STD 95% 卡方区间、轴间相关性及 bias/scale 注入测试。P-10 的多速率队列、sample/capture/arrival 和缺测计数已有独立 `verify_sensor_event_timing`；GNSS PPS raw capture 与 UTC epoch/time-domain mapping 尚未实现，`pps_backend` 明确为 `DISABLED_LOCAL_MONOTONIC`，因此 P-10 整体仍为 PARTIAL。P-14 已由 verify_truth_isolation 实现并纳入 run_component_checks。

本阶段需在用户 MATLAB 环境执行 run_component_checks；该入口会先运行输入预检、重建 build_native_kernels、生成参数字典，再执行 verify_parameter_view、verify_plant_open_loop（内部调用 verify_sensor_event_timing）及已实现组件检查。也可单独执行 build_native_kernels、generate_parameters、verify_parameter_view 和 verify_plant_open_loop；后者会调用 verify_sensor_event_timing。需要只调试队列时可单独执行 verify_sensor_event_timing。必须保存实际运行报告、MATLAB 版本、求解器与模型 Hash。Plant 报告必须保持 PARTIAL，不能解释为完整物理模型验收、HIL 实时性 PASS 或实机飞行放行。

## P-10b 时间服务核心回归（代码状态）

- 新增 fmt_time_service_probe MEX wrapper，直接编译同级 Flight/sensor_device/time_base/systime.c，并调用上游 Flight/tests/time/test_time_service.c，不复制或重写 TimeService 算法。
- build_native_kernels 会构建该 MEX；run_component_checks 会执行 verify_time_service_sync 并保存 work/validation/time_service_sync_report.json。
- 上游测试覆盖单调时间映射、PPS 周期门限/频率锁定/失锁 holdover、UTC observation 必须与 PPS 配对、UTC 映射不确定度、外部时钟映射和 time_epoch 不连续拒绝。
- 该回归使用合成 PpsCaptureEvent 与确定性 tick source，只证明 TimeService 核心算法；不证明 TIM2 capture ISR、UM982 UART RECTIME 解码、PPS/UTC 在 MILSIM 中端到端运行。当前 Flight/tests/simulation/sil_flight.c 的时间服务接口仍为 STATUS_NOT_READY stub，故 P-10 整体保持 PARTIAL。
- MATLAB/MEX 编译与执行尚未在本次环境运行；本阶段代码状态不能写成实测 PASS。
