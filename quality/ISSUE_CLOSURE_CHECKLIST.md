# 问题关闭验收清单

每个 GitHub Issue 在关闭前逐项确认。任何一项不满足，保持 Open。

- [ ] Issue ID、类型、严重级别、模块和状态完整。
- [ ] 发现时的 RUN_ID、分支/commit、Flight 上游 commit 已记录。
- [ ] 原始失败报告、Diary 和相关输入数据有 SHA-256 证据。
- [ ] 复现步骤、期望/实际结果和影响范围明确。
- [ ] 根因已由证据确认；若不是缺陷，结案理由已说明。
- [ ] 修复 PR/commit 已关联，变更范围可审查。
- [ ] 修复后的新 RUN_ID 与精确源码/配置/数据指纹匹配。
- [ ] 原失败用例回归通过。
- [ ] 受影响的邻接测试和必要的完整验收入口通过。
- [ ] 没有将 PARTIAL、NOT_RUN、UNVERIFIED 误记为 PASS。
- [ ] S0/S1 安全影响已单独复核。
- [ ] Issue 正文已更新结论，评论已记录状态变化、证据和日期。
- [ ] 结案类型为 VERIFIED、DUPLICATE 或 NOT_PLANNED；DUPLICATE/NOT_PLANNED 已链接依据并获用户接受。
