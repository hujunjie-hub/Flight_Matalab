# 验收归档证据模型（manifest schema 1.1）

本文件说明 `tools/archive_validation_run.ps1` 产出的 `run_manifest.json` 里各个指纹、状态和分类字段的含义，以及它们为什么不能合并成一个数字。

## 1. 旧模型的问题

schema 1.0 只有 `source_fingerprint_sha256` 一个摘要，而 `tools/fingerprint_sources.py` 会把下面这些**构建步骤自己生成**的文件也算进去：

- `models/**/*.slx`、`simulation/**/*.slx`、`tests/**/*.slx`
- `dictionaries/**/*.sldd`
- `work/mex/*.mexw64`
- `scenarios/*.mat`

后果有三个，都在 FMAT-0008 的验收里实际出现过：

1. 同一份源码每跑一轮指纹就变一次（`7c514e63…` → `275e8374…` → `857d6d6d…`），无法用指纹判断"是不是同一套代码"；
2. 运行中被重新保存的模型与真正的源码改动混在同一个摘要里，未提交的生成结果看起来像已提交源码；
3. 干净工作区与脏工作区没有区别，manifest 只能记一串 `git status` 文本。

## 2. 两种指纹

| 指纹 | 覆盖范围 | 回答的问题 |
|---|---|---|
| **source** | `tools/`、`tests/`、`config/`、`interfaces/`、`models/`、`simulation/` 下的 `.m .c .h .py .ps1 .json .yaml .yml`，加 `external_dependencies.lock.json` | 这次运行用的是哪份**源码输入** |
| **artifact** | `*.slx`、`*.sldd`、`work/mex/*.mexw64`、`work/runtime/*.dll`、`scenarios/*.mat`、`work/validation/*.mat` | 这次运行实际加载的**生成产物** |

`work/validation/archives/**`、`work/dependencies/**`、`work/cache/**` 不参与 artifact 扫描，否则指纹会随历史归档一起变化。

### 2.1 source 指纹的三个字段

`work/validation/current_source_fingerprint.json`：

| 字段 | 含义 |
|---|---|
| `committed_sha256` | 对 `git ls-tree -r HEAD` 中在册源码 blob 的摘要。**只由已提交内容决定**，工作区再脏也不变 |
| `sha256` | 对磁盘上同一批文件内容的摘要，代表"实际被加载的那份" |
| `clean` / `dirty_files` / `untracked_files` | 由 `git status --porcelain` 判定，已应用仓库的换行符与属性过滤器（本仓库 `core.autocrlf=true`，直接比对 blob 会把每个文件都判成脏） |

两者同时给出，就是为了满足"不允许把未提交的生成结果冒充已提交源码"：`committed_sha256` 说明基线，`sha256` 说明实测对象，`clean=false` 时 manifest 会列出具体脏文件。

### 2.2 artifact 指纹

`work/validation/current_artifact_fingerprint.json` 记录每个生成产物的 SHA-256、按 `simulink_model` / `data_dictionary` / `mex_kernel` / `recording` 分组，并给出整体摘要。重建模型只会改这个摘要，不会动 source 摘要。

## 3. 生成文件分类

`work/validation/generated_assets.json` 把运行前后 `git status` 与两次 artifact 摘要对比，逐文件给出 `class` 和 `disposition`：

| disposition | 含义 | 处理建议 |
|---|---|---|
| `commit_candidate` | 运行新生成、尚未被 git 跟踪的模型/字典 | **应提交的正式模型资产**（例如本分支新增的 `models/plant/FMT_PlantSensors.slx`） |
| `regenerated_by_run` | 运行前干净、运行后被重新生成 | 可恢复的自动布局修改，`git checkout --` 即可还原；不应随证据提交 |
| `pre_existing_local_change_modified_by_run` | 运行前就已修改，**且本次运行又改写了它** | 归因明确：该文件既是用户既存修改，也是本轮产物；不得在结论里当作"用户未动过" |
| `pre_existing_local_change` | 运行前就已修改，本次运行**未**再改变 | 无法归因到本次运行，需人工确认 |
| `restored_during_run` | 运行前脏、运行后恢复干净 | 记录即可 |
| `excluded_from_source` | `work/` 下的编译产物（mex/dll/slprj 等） | 临时构建产物，永不进入源码 |
| `uncommitted_source_change` | 源码文件在运行前就未提交 | 该轮结果的源码基线不是 HEAD，需在结论中说明 |
| `documentation_change` | `.md`/`.txt` 改动 | 不影响指纹 |

局限必须写明：**无法仅凭字节判断一个 `.slx` 是否只是自动布局差异**。因此分类只声称"该文件在运行前是干净的、运行结束后字节变了"，而不声称"语义未变"。要证明语义，需要模型级比较，这不在本模型的范围内。

脏工作区不能只用一个类别概括：运行前已修改的文件，本次运行可能又把它改写了（例如 MIL 重新生成的录制 MAT），也可能完全没碰。`generated_assets.json` 用运行前后的 artifact 摘要区分这两种情况，分别记为 `pre_existing_local_change_modified_by_run` 和 `pre_existing_local_change`。分类**只描述归因**，不会清除任何用户已有的模型、字典或录制文件。

## 4. 运行前后快照

| 文件 | 生成时机 | 内容 |
|---|---|---|
| `git_state_before.json` | `run_component_checks` 第一步 | 分支、commit、subject、逐条 `git status` |
| `source_fingerprint_before.json` | 同上 | 运行前 source 指纹 |
| `artifact_fingerprint_before.json` | 同上 | 运行前产物摘要 |
| `git_state_after.json` | 检查结束或异常退出 | 运行后工作区状态 |
| `source_fingerprint_after.json` | 同上 | 运行后 source 指纹（应与运行前一致） |
| `current_source_fingerprint.json` | 同上 | 归档脚本读取的正式 source 指纹 |
| `current_artifact_fingerprint.json` | 同上 | 正式产物摘要 |
| `generated_assets.json` | 同上 | 分类表 |

`run_component_checks` 在 try 和 catch 两条路径上都会写入 after 快照；断言 `source_fingerprint == fingerprint(root)` 仍然保留，用来证明检查期间源码输入没有变化。

## 5. 失败与提前退出

`archive_validation_run.ps1` 在枚举待归档文件**之前**检查 `git_state_after.json` 与 `current_artifact_fingerprint.json`，缺失时用当前状态补生成；manifest 的 `archive_completeness` 逐项记录：

```json
"archive_completeness": {
  "component_report": false,
  "source_fingerprint": true,
  "artifact_fingerprint": true,
  "git_before": true,
  "git_after": true,
  "generated_assets": false
}
```

配合 `component_status = "NO_COMPONENT_REPORT"`，失败运行既不会伪装成成功，也不会丢证据。补生成的快照会随 ZIP 一起归档，归档成功后当前 `work/validation/` 顶部文件仍按原规则清空。

## 6. 测试

| 套件 | 覆盖 | 运行方式 |
|---|---|---|
| `tests/verify_archive_reliability.m`（A-01…A-08） | 同源码确定性、干净工作区、脏工作区、模型重建不污染 source 指纹、重建后重复运行稳定、分类正确、运行前脏且被本轮改写、运行前脏且未被本轮改写 | 已接入 `run_component_checks` 的 `archive_reliability` 门 |
| `tests/verify_archive_failure_path.ps1`（F-01…F-05） | MATLAB 中途崩溃后 before 快照保留、归档补生成 after 状态、manifest 如实报告缺件、ZIP 内含两份快照、脏工作区被记录 | `pwsh -File .\tests\verify_archive_failure_path.ps1` |

两者都在临时 git 夹具上运行，不依赖真实工作区的未提交状态，单次执行均在秒级到一分钟之间。

## 7. 已知边界

1. 指纹描述"这次运行实际加载了什么"，**不构成模型语义等价的证明**；
2. 依赖 `git` 与 `python` 可用，缺失时相关字段为 `UNAVAILABLE`/`UNKNOWN`，不会被当作有效值；
3. `committed_sha256` 只覆盖上述源码目录；`spec/`、`docs/` 等文档目录不入指纹；
4. 本模型不改变 `run_component_checks` 中任何物理/控制门的判定，只让证据更可追溯。
