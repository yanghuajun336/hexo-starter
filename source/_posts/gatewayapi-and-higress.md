---
title: "理解 Gateway API 与 Higress：规范与实现的关系（实践指南）"
date: 2025-11-28 12:30:00
categories:
- Kubernetes
- Gateway API
- Higress
tags:
- gateway-api
- higress
- ingress
- kubernetes
---

摘要
----
本文以实践视角解释 Gateway API（规范）与 Higress（实现）之间的关系，何时使用它们、如何理解常见概念、以及在集群中部署与调试时应注意的关键点。面向正在从 Ingress 迁移或者准备引入 Gateway API 的平台与应用开发者。

什么是 Gateway API（简明）
------------------------
Gateway API 是 Kubernetes SIG-Networking 推出的下一代边缘流量 API，一套由 CRD 构成的规范，目标代替传统 Ingress 的表达能力限制。核心设计目标包括：
- 将网关（Gateway）职责与路由（Route）职责分离；
- 支持多协议、多端口、多监听器（Listener）与更丰富的匹配规则；
- 更好地支持多团队、跨命名空间委托与权限控制（ReferenceGrant）；
- 提供可扩展的“平台管理员负责网关，应用开发者负责路由”的工作流。

关键概念（快速参照）
- GatewayClass：类似于 StorageClass，定义一种网关实现类型，由某个 controller 负责实现（通过 controllerName 识别）。
- Gateway：在命名空间内的网关实例，绑定到 GatewayClass，包含 Listeners（端口/协议/TLS）。
- Listener：定义端口、协议，以及允许哪些 Routes（路由）被挂载。
- Routes（HTTPRoute / TCPRoute / TLSRoute / GRPCRoute / UDPRoute）：定义流量匹配规则与后端（backendRef）。
- ReferenceGrant：跨命名空间引用授权机制，允许安全地引用外部资源。

什么是 Higress（简明）
--------------------
Higress 是一个 Gateway API 的实现 / 控制器。它：
- 监听 Gateway API 的 CRD（GatewayClass/Gateway/HTTPRoute 等）；
- 将 CRD 定义转换为实际的数据平面配置（如 Envoy、内置代理或其它实现）；
- 提供 controllerName（例如 higress.io/controller），GatewayClass 的 spec.controllerName 必须匹配这个值，才能被 Higress 认领和控制。

规范 vs 实现：如何理解它们的关系
------------------------------
- Gateway API = 规范（契约）：定义“应该如何描述网关与路由”；
- Higress = 实现：把规范内容监听、解析并下发到数据平面（代理/负载均衡器）。
换言之：你创建 Gateway/HTTPRoute，只是“写规则”；Higress 见到这些规则后负责“把规则变成可执行配置”。

部署与使用的典型流程
--------------------
1. 安装 Gateway API 的 CRD（注意与 Kubernetes 版本兼容）  
2. 部署 Higress controller（或其它支持 Gateway API 的控制器）  
3. 创建 GatewayClass，spec.controllerName = Higress 的 controllerName  
4. 创建 Gateway（绑定 GatewayClass），并定义 Listeners  
5. 创建 HTTPRoute 等，将 parentRef 指向 Gateway，backendRef 指向 Service  
6. 检查资源 Conditions 与 controller 日志，确认被採纳并下发配置

示例（最小化 YAML）
```yaml
# GatewayClass
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: GatewayClass
metadata:
  name: higress-class
spec:
  controllerName: higress.io/controller

# Gateway
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: Gateway
metadata:
  name: higress-gateway
  namespace: default
spec:
  gatewayClassName: higress-class
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      routes:
        kind: HTTPRoute
        namespaces:
          from: All

# HTTPRoute
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: HTTPRoute
metadata:
  name: example-route
  namespace: default
spec:
  parentRefs:
    - name: higress-gateway
  hostnames:
    - "example.local"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-svc
          port: 80
```

常见注意事项与陷阱
--------------------
- 仅安装 CRD 不够：必须有一个实现（Higress / Contour / Kong / Istio 等）正在运行，否则 Gateway/Route 没有控制器认领将不会生效。  
- controllerName 必须匹配：GatewayClass.spec.controllerName 要与控制器期望的字符串一致。  
- 版本兼容性：Gateway API 的 manifest 可能使用 CRD schema 扩展（如 x-kubernetes-validations）；旧版 Kubernetes（例如 v1.21）可能需要 sanitize 清单或升级集群。  
- RBAC：controller 需要读写 Service、Endpoints、ConfigMap 等资源的权限，确保安装时 RBAC 足够。  
- ReferenceGrant：跨命名空间引用需要显式授权，避免因权限问题无法挂载 Route。  
- 调试：先看 Gateway/HTTPRoute 的 Conditions 字段，再看 controller Pod 日志（controller 会给出被拒绝或未被採纳的原因）。

常用调试命令
----------------
kubectl get gatewayclasses
kubectl get gateway -A -o wide
kubectl describe gateway <name> -n <ns>
kubectl get httproute -A
kubectl describe httproute <name> -n <ns>
kubectl get pods -n <controller-namespace>
kubectl logs -n <controller-namespace> <controller-pod-name>

结语
----
把 Gateway API 看成“统一的网关/路由 DSL”，把 Higress 看成“解释器/编译器”。二者搭配可以把平台能力以 API 形式稳定暴露给应用团队，同时保留管理员对数据平面的控制权。在生产环境中，请务必关注：CRD 与 K8s 版本兼容性、controller 的 RBAC 与可用性，以及跨命名空间引用的授权策略。
