# QuadPlant 实施计划

状态：P1/P2 源码已按 Flight 参数与接触规格更新；MATLAB 验证 NOT_RUN。2026-11-09。

| 阶段 | 交付 | 当前状态/退出检查 |
|---|---|---|
| P0 物理接口冻结 | u/w/y/z bus、CG/frame/q/rate约定、参数表 | 已有规格；仍需核对所有接口与实际模型 |
| P1 电机/分配载荷 | MotorDynamics、RotorWrench组件 | 源码已有；参数矩阵改为从 Flight 通用推导；需 MATLAB 数值回归 |
| P2 刚体/接触 | 17维 PlantState/四阶段 RK4、Environment、几何门控 GroundContact | 源码已增加完整惯量、Cholesky 求解、输入 fail-closed、静态压缩和独立步长参考；需 MATLAB 数值回归 P-04..P-06、P-11..P-13、P-15..P-21 |
| P3 传感器 | 采样、杆臂、Earth项、noise/bias/delay | 已实现 CG→IMU 杆臂加速度、IMU→GNSS 天线位置/速度、固定 N0 Earth/Coriolis 和首样本差分门控；P07/P08 有组件测试。P09 seeded noise/bias/scale 已实现；P10a 多速率队列已接入并测试；P10b 真实 Flight TimeService 与 GNSS outage/recovery 核心已由两个 MEX 复用上游 host suite 回归，Host MIL 的 TIM2 capture/UM982 RECTIME 端到端接入仍未完成 |
| P4 物理侧集成 | FMT_QuadPlant/FMT_PlantSensors/FMT_MILSIM | 独立传感器运动学探针已加入；需 MATLAB 编译/仿真、接口因果链、无代数环和输出单位测试 |
| P5 系统闭环 | 仅接 M7 已提交帧与 M2 标准入口 | `verify_truth_isolation` 已加入结构门；P09、P10a 队列与 P10b TimeService/GNSS outage 核心均有代码测试，但 Host MIL PPS/RECTIME 注入链及共享 FCS 尚未验收，不进入完整 MIL 验收 |

物理参数来源：Flight/config/vehicle_model.yaml 提供质量、完整惯量、电机位置、偏航力矩符号、推力上下限和电机时间常数；Flight Host SIL runtime 提供 gravity；SIM_ONLY 配置提供 kf、drag、contact、Origin、地面摩擦和传感器场。PlantParameters 为 26 项，Plant/Allocator/INS 参数在 .sldd 中统一生成，不在模型 Mask 中复制独立参数。

建模按最小 scope 执行 model_read→model_edit→model_check；遇 partial 立即检查并修正。每阶段保存接口/模型 Hash 和测试输出，不将完整闭环成功当作组件符号正确的唯一证据。

物理 Plant 先用 double，公开固件兼容 bus 按 single 转换；运行精度不同必须写入 manifest。每个新增 fidelity 层重新跑步长/能量/传感器一致性检查。当前不声称 HIL 实时性或飞行安全放行。
