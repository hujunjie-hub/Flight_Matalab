# QuadPlant 实施计划

状态：NOT_STARTED；2026-11-05。本轮不创建或改动模型。

| 阶段 | 交付 | 依赖/退出检查 |
|---|---|---|
| P0 物理接口冻结 | u/w/y/z bus、CG/frame/q/rate约定、参数表 | 系统G0-HOST；明确固定N0/当前地理NED和ω_b/N0/ω_ib语义 |
| P1 电机/分配载荷 | MotorDynamics、RotorWrench组件 | 单电机/对称推力/一阶响应通过 |
| P2 刚体/接触 | 17维PlantState/四阶段RK4、Environment、几何门控GroundContact | 自由落体/静态平衡/空中无接触阻尼/固定原点/步长细化通过 |
| P3 传感器 | 采样、杆臂、Earth项、noise/bias/delay | 静止比力、旋转杆臂和时间戳测试通过 |
| P4 物理侧集成 | FMT_QuadPlant/FMT_SensorSimulation模型引用 | 开环因果链、无代数环、输出单位正确 |
| P5 系统闭环 | 仅接M7已提交帧与M2标准入口 | FMS/Control合格后运行MIL；truth无捷径 |

物理参数来自SIM_ONLY四份CORE，结构/安全参数来自readonly Profile，.sldd为生成视图。不得同时保留旧plant_model_init及新Mask中的独立mass/J/Ct。旧MC-Plant只读参考，未来选定复用的子系统应记录原文件/SID、复制范围、许可证及修改原因。

建模按最小scope执行model_read→model_edit→model_check；遇partial立即检查并修正。每阶段保存接口/模型Hash和测试输出，不将完整闭环成功当作组件符号正确的唯一证据。

物理Plant先用double，公开固件兼容bus按single转换；运行精度不同必须写入manifest。每个新增fidelity层重新跑步长/能量/传感器一致性检查。当前所有P阶段均NOT_STARTED，所有Plant测试均NOT_RUN。
