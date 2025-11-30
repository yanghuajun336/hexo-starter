---
title: "Gateway + HTTPRoute：主机名不匹配导致路由无效（实战总结）"
date: 2025-11-30 12:00:00
tags:
  - Kubernetes
  - GatewayAPI
  - Higress
  - HTTPRoute
categories:
  - 运维
  - 路由
---

本文总结了一次在 Higress/Gateway API 环境中，HTTPRoute 无法生效的排查与修复过程。

背景
- 集群用了 Higress 作为 Gateway API 的实现（gateway 名为 `higress-gateway`）。
- Gateway 上配置了若干 HTTPS listener：`services.zlinkcloudtech.com`（名为 `https`）、`blog.zlinkcloudtech.com`（`https-blog`）、`workflow.zlinkcloudtech.com`（`https-workflow`）、`repo.zlinkcloudtech.com`（`https-repo`）等。
- 我们在 `app-harbor` 命名空间创建了一个 `HTTPRoute`，host 是 `repo.zlinkcloudtech.com`，parentRef 指向 `higress-gateway` 并使用 `sectionName: https`（对应 `services.zlinkcloudtech.com`）

现象
- `kubectl describe httproute harbor-route -n app-harbor` 报错：
  `no hostnames matched parent hostname "services.zlinkcloudtech.com"`。
- Route 被 Controller 拒绝（Accepted=false），但 `ResolvedRefs` 为 True（说明后端引用没问题）。

分析
- Gateway API 的约束：当 `HTTPRoute` 指定 `parentRef` 并绑定到某个 listener（通过 `sectionName`），该 `HTTPRoute` 的 hostnames 必须与 listener 的 `hostname` 匹配；否则 Controller 会拒绝该 Route。原因是防止将 `A` hostname 的流量误导到 `B` 的 Listener，从而破坏域名隔离性。
- 在我们的 case 中：
  - `HTTPRoute` 的 `hostnames: [repo.zlinkcloudtech.com]`，但 `sectionName: https`（listener 的 hostname = `services.zlinkcloudtech.com`） —— 不匹配。
  - 解决办法：把 Route 的 `sectionName` 改为 `https-repo`（对应 Gateway 上的 `repo.zlinkcloudtech.com` listener），或把 `hostnames` 改为 `services.zlinkcloudtech.com` 并放置在正确的 listener 中。

修复步骤（建议）
1. 查看 Gateway listener 列表，确认 listener 名称与 hostname：

```bash
kubectl describe gateway higress-gateway -n higress-system
```

2. 把 route 的 `parentRefs.sectionName` 改为 `https-repo`（示例）：

```bash
kubectl patch httproute harbor-route -n app-harbor \
  --type='merge' \
  -p '{"spec":{"parentRefs":[{"name":"higress-gateway","namespace":"higress-system","sectionName":"https-repo"}]}}'
```

或直接编辑：

```bash
kubectl edit httproute harbor-route -n app-harbor
# 修改 parentRefs 的 sectionName
```

3. 验证 Route 状态：

```bash
kubectl describe httproute harbor-route -n app-harbor
kubectl describe gateway higress-gateway -n higress-system
```

状态应该显示 `Parents.Accepted=True`、`Parents.ResolvedRefs=True`、`Programmed=True`，并且 `Attached Routes` 包含该 route。

测试访问（NodePort 临时测试）：

```bash
# 假设 Higress 的 NodePort 30443, node IP 为 <node-ip>
curl -vk https://<node-ip>:30443/ -H "Host: repo.zlinkcloudtech.com"
```

注意事项与拓展
- `allowedRoutes.namespaces`：Gateway API 不支持直接按命名空间名数组匹配，只支持 `All`、`Same` 或 `Selector`。若要「允许 app-blog namespace」，可以在目标 namespace 上加 label（例如 `gateway.allowed=true`），然后在 Gateway 配置里使用 selector。示例：

```bash
kubectl label namespace app-harbor gateway.allowed=true --overwrite
```

- 若 `ResolvedRefs=False`：检查 backendRef 的 Service 名称和 port 是否正确；另外确认 backend Service 是否存在并有可用 endpoints。
- 若 `Programmed=False`：通常是 Gateway 的 External IP pending 或网络层问题（LoadBalancer 未分配 IP），这会阻止流量对外发布。

结语
- Gateway API 的设计在域名与 listener 的绑定上有明确的校验，当你更改 host 或 listener 名称时，请始终保持 `HTTPRoute.hostnames` 与 `Gateway` 的 listener hostname 匹配，或把 `sectionName` 指向正确的 listener，以确保 Controller 能正确下发数据平面配置。

