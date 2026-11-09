# FlightSIM 系统规格

状态：设计草案；2026-11-05。父级：[固件总体架构](../../Flight/spec/01_系统总体架构与设计决议.md)。

## 1. 目标和当前差距

在现有FMT-Model资产上重组为新版M1～M7架构，保留可核验的数学/物理资产，将新工程交付到Flight_Matalab。当前实际源入口没有FMT前缀；CF-INS/Controller/Plant周期2ms，MC-FMS周期4ms；旧Control_Out为16路uint16、时间为uint32毫秒，均不能直接充当新版物理推力/64位微秒接口。

| 需求 | 明确结果 | 验收 |
|---|---|---|
| FSYS-001 | 三个FMT前缀入口在新工程simulation内存在且能独立运行 | T-SYS-01 |
| FSYS-002 | 共享同一FMS、Guidance、Control、M7实现 | T-ARCH-01、T-GDN-01～09、T-MAP-01 |
| FSYS-003 | FMS及源健康/参考生命周期用Stateflow实现 | T-FMS-01～12 |
| FSYS-004 | M5完整规划/连续验证，M6为可见的Simulink MPC→SO(3)→Rate PID→分配链 | T-CTL-01～11 |
| FSYS-005 | 公共数据按选定上位Schema/Product快照、NED/FRD、CG和物理单位传递 | T-ICD-01～05 |
| FSYS-006 | M3为项目KF-GINS_QUAD22；外部参考保留原生KF21；固定GNSS/PPS，支持运行中失锁与恢复 | T-INS-01～08、T-GNSS-01～06 |
| FSYS-007 | 测量时间、到达时间、State Time、Control Time分离 | T-TIME-01～11 |
| FSYS-008 | 无PlantTruth动态反馈捷径、无旧权限/参考复用 | T-ARCH-02、T-FMS-03 |
| FSYS-009 | 数据/配置/软件来源和运行报告可追溯 | T-DATA-01～06 |
| FSYS-010 | 原FMT-Model、Flight固件/官方资料及上位spec保持不变 | T-SPEC-02 |

## 2. 三种运行模式

### FMT_DataSIM

输入为有manifest的原始传感器、操作员/链路事件和任务记录；内部运行M2、M3及共享FMS/控制链。M7为虚拟提交/编码校验，不存在物理Plant。可比较估计误差和算法确定性；不能把新控制输出与历史飞行建立因果闭环，也不能要求新物理Nm增益复现旧归一化PWM。

### FMT_MILSIM

唯一的系统物理闭环：控制/输出→执行器动态→机体→传感器→估计器→控制。外部扰动、故障和操作脚本为外生输入；真实状态仅进入传感器合成及只读评价。GroundContact为显式SIM_ONLY接触传感器，不能由真实姿态真值绕过估计器生成导航。

### FMT_ExtINS_DataSIM

FCS只消费经适配的ExternalNavigationBundle。默认外部数据由锁定原生KF-GINS MATLAB21离线产生；也可输入有完整语义的既有外部导航日志。内部M3不参与活动导航发布；可选shadow比较只能到评价端，不能融合两套结果冒称更好精度。项目22维离线参考是独立PROJECT22 profile，不能替换PRISTINE21黄金。

## 3. 产品边界

执行变体选定HOST_NATIVE_V2：本目录的retimed planner、参考grid、活动/准备协议及双时钟可直接作为Host建模输入；未来固件等价需独立门槛，不因复用C值类型自动成立。

首版QUAD_X4；不扩展UGV/USV。首版模型为Host/MIL，不交付H723驱动、RTOS调度代码、硬件通讯、在线升级或试飞许可。首次验收不依赖Joystick、FlightGear、UE4、VR Sink或UDP；可视化默认关闭，日志与离线图是基本交付。

本产品固定配备UM982（UART4、460800、PVT 10Hz）及PA2/TIM2_CH3 PPS（1Hz）；GNSS/PPS在目标Manifest中均必须存在并启用。主平台可复用性不意味着本机器件可选：其他产品的无GNSS Profile不属于本次交付。短暂失去卫星/PVT/PPS时保持同一产品配置，按各源质量、时间映射和导航能力降级；不切换到未安装状态，不保证无GNSS时长期保持水平定位。最新源配置已强制接入UART4/RX DMA及PPS；原生GNSS后端/时间与标定证据尚未接纳的差异由FirmwareConformanceGate跟踪，本规格不把现状缺口当设计选择。

| Profile | 导航/物理 | 输出 | 用途 |
|---|---|---|---|
| QUAD_SIM_CLOSED_LOOP | M3项目22+合成传感器+Plant | SIM_CONTROLLED_STOP(2) | MIL闭环 |
| QUAD_RAW_REPLAY | M3项目22+合格1kHz原始记录 | 虚拟M7，无Plant | DataSIM |
| QUAD_EXTNAV_REPLAY | 外部Nav适配器 | 虚拟M7，无Plant | ExtINS_DataSIM |
| KF21_REFERENCE_ONLY | 原生数据率、原生21维参考 | 不授予运动Permit | 上游原生数据集复现 |

H723的BENCH_INHIBIT和辅助源禁用是固件现状；Host的SIM_ONLY合成辅助源可以启用，但不能反推实机已经接纳。所有Profile通过RunManifest区分并进入hash。

## 4. 运行与性能目标

默认有限30s；快速冒烟2s。MIL名义基步0.5ms、IMU/快控1ms、FMS10ms、Guidance/MPC20ms、输出2.5ms。回放不把任意原生数据率伪造成1kHz。

| 场景/指标 | 设计接纳值 | 适用依据 |
|---|---|---|
| 30s名义任务 | 无NaN/Inf、无未处理事件溢出、无不合法授权提交 | 功能确定性 |
| 悬停区间7～10s | 位置误差RMS≤0.25m，姿态误差RMS≤3deg | SIM_ONLY整定目标，待仿真验证 |
| 0.5rad/s速率阶跃 | 1.5s内进入±5%，超调≤30% | 初始SIM控制目标 |
| 合法同输入重放 | 离散状态/拒绝码相同；浮点按测试计划容差 | 可重复性 |
| q范数 | 误差≤1e-6 | 数值一致性 |
| TTL/epoch拒绝 | 下一次消费者执行即拒绝；M7下一帧不得用旧token | 上位ICD |

这些是验收门限，不是当前PASS。Host墙钟耗时与H723 WCET/RTA单独记录，不互相替代。

## 5. 进入改造前的交付

本轮交付本文档集、来源清单及静态审查结果。Phase0需确认共享bus、速率、Stateflow状态/输出、MPC求解器及参考数据可用性；未通过前只能准备接口和依赖，不能以空壳或持续PD fallback宣布三个最终模型完成。
