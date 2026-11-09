# QuadPlant 实施计划

状态：P1/P2 源码和参数合同已更新；MATLAB/Simulink 验证仍 NOT_RUN。2026-11-09。

| 阶段 | 交付 | 当前状态/退出检查 |
|---|---|---|
| P0 物理接口冻结 | u/w/y/z bus、CG/frame/q/rate约定、参数表 | 已有规格；仍需核对所有接口与实际模型 |
| P1 电机/分配载荷 | MotorDynamics、RotorWrench组件 | 源码已有；参数矩阵改为从 Flight 通用推导；需 MATLAB 数值回归 |
| P2 刚体/接触 | 17维 PlantState/四阶段 RK4、Environment、几何门控 GroundContact | 源码已有；完整惯量张量、fail-closed 输入检查和静态压缩测试已补充；需 MATLAB 数值回归 P-04..P-06、P-11、P-15..P-20 |
| P3 传感器 | 采样、杆臂、Earth项、noise/bias/delay | 当前只实现固定 N0 Earth/Coriolis 与确定性基础测量；杆臂、噪声、bias、队列/延迟仍未完成 |
| P4 物理侧集成 | FMT_QuadPlant/FMT_SensorSimulation模型引用 | 有基础模型；需接口因果链、无代数环和输出单位测试 |
| P5 系统闭环 | 仅接 M7 已提交帧与 M2 标准入口 | FMS/Control 合格后运行 MIL；truth 无捷径 |

物理参数来源：Flight/config/vehicle_model.yaml 提供质量、惯量、电机位置、偏航力矩符号、推力上下限和电机时间常数；Flight Host SIL runtime 提供 gravity；SIM_ONLY 配置提供 kf、drag、contact、Origin 和传感器场。Plant 参数向量为 25 元素并在 .sldd 中统一生成，包含完整 J(:)；不在模型 Mask 中复制独立参数。

建模按最小 scope 执行 model_read→model_edit→model_check；遇 partial 立即检查并修正。每阶段保存接口/模型 Hash 和测试输出，不将完整闭环成功当作组件符号正确的唯一证据。

物理 Plant 先用 double，公开固件兼容 bus 按 single 转换；运行精度不同必须写入 manifest。每个新增 fidelity 层重新跑步长/能量/传感器一致性检查。当前不声称 HIL 实时性或飞行安全放行。
