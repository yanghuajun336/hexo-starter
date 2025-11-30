---
title: "PhotoPrism 在 Kubernetes 上 CrashLoopBackOff 的排查与 Gateway API / Higress 兼容性处理实战"
date: 2025-11-28 12:00:00
categories:
- Kubernetes
- PhotoPrism
- Gateway API
- Higress
tags:
- photoprism
- gateway-api
- higress
- troubleshooting
---

摘要
----
本文记录一次在 Kubernetes 上部署 PhotoPrism 时遇到 CrashLoopBackOff 的完整排查过程，以及在安装 Gateway API CRD（用于 Higress）时遇到的兼容性问题与解决办法。文中包含了要运行的命令、分析思路与最终的解决方案，便于在类似场景中快速定位与修复。

环境说明
---------
- Kubernetes Server: v1.21.1
- kubectl Client: v1.34.2
- PhotoPrism 镜像: photoprism/photoprism:250321
- 部署方式: Helm chart（StatefulSet，使用 PVC）
- 目标：启动 PhotoPrism 并安装 Gateway API CRD 供 Higress 使用

一、问题现象（简述）
-------------------
部署后 Pod 一直处于 CrashLoopBackOff，kubectl logs 看到 PhotoPrism 启动日志能走到打开 SQLite，但随后 s6 停止服务并退出；同时 kubectl describe pod 有大量 probe 报错（connection refused），并且事件里早期出现 hostPath 找不到的错误：Error: stat /root/software/k8s/photoprism/volume/originals: no such file or directory。

核心日志片段（简化）：
```log
time="..." level=info msg="database: opened connection to SQLite v3.45.1"
...
s6-rc: info: service legacy-services: stopping
s6-rc: info: service legacy-cont-init: stopping
s6-rc: info: service fix-attrs: stopping
s6-rc: info: service s6rc-oneshot-runner: stopping
```

Events 中的关键行：
```text
Warning  Unhealthy  Readiness probe failed: Get "http://10.244.0.13:2342/": dial tcp 10.244.0.13:2342: connect: connection refused
Warning  Failed     Error: stat /root/software/k8s/photoprism/volume/originals: no such file or directory
```

二、定位思路与排查步骤（按顺序）
------------------------------
下面是按顺序执行的排查步骤与观察点（包含常用命令）：

1) 查看 Pod 状态与事件（找 Exit Code / Reason / Events）
- 命令：
  kubectl get pods -o wide
  kubectl describe pod <pod-name>

2) 获取容器日志（包括前一次实例）
- 命令：
  kubectl logs <pod>
  kubectl logs -p <pod>

3) 查看集群事件（筛查与存储、调度、OOM 等相关的全局事件）
- 命令：
  kubectl get events --sort-by=.metadata.creationTimestamp

4) 检查 PVC / PV / hostPath 配置（是否挂载成功、节点路径是否存在）
- 命令：
  kubectl get pvc -o wide
  kubectl describe pvc <pvc-name>
  kubectl get pv
  kubectl describe pv <pv-name>

5) 检查容器探针（liveness/readiness）的配置是否过激
- 在 StatefulSet 或 Deployment 定义里查看探针：
  kubectl get statefulset <name> -o yaml  
  或
  kubectl edit statefulset <name>
- 典型问题：initialDelaySeconds 太短、timeout 太小、failureThreshold 低 -> 导致启动未完成就被杀掉

6) 尝试进入容器或使用 debug pod 挂载相同 PVC 手动启动应用观察行为
- 创建 debug pod 并挂载 PVC：
  kubectl run photoprism-debug --rm -it --image=photoprism/photoprism:250321 --overrides='
  {"apiVersion":"v1","kind":"Pod","metadata":{"name":"photoprism-debug"},"spec":{"containers":[{"name":"photoprism-debug","image":"photoprism/photoprism:250321","command":["/bin/sh"],"args":["-c","sleep 1d"],"volumeMounts":[{"name":"storage","mountPath":"/photoprism/storage"},{"name":"originals","mountPath":"/photoprism/originals"}]},"volumes":[{"name":"storage","persistentVolumeClaim":{"claimName":"storage-pvc"}},{"name":"originals","persistentVolumeClaim":{"claimName":"originals-pvc"}}],"restartPolicy":"Never"}}' -- /bin/sh

7) 检查 /photoprism/storage/config/settings.yml、sqlite 文件、权限等（在 debug pod 中）
- 命令（在 pod 里）：
  ls -la /photoprism
  ls -la /photoprism/storage
  cat /photoprism/storage/config/settings.yml

三、分析与结论（从现有输出得出的关键线索）
--------------------------------
1. 事件里有明确的 hostPath 找不到错误：Error: stat /root/software/k8s/photoprism/volume/originals: no such file or directory -> 说明 PV（或 hostPath）在节点上指向了一个不存在的本地路径（若 PV 使用 hostPath）或 NFS 挂载失败。
2. 日志显示 Photoprism 能打开 SQLite，说明进程并非瞬间崩溃，而是可能被 s6 机制停止（容器关键服务停止）、或被 kubelet 的 liveness/readiness 探针判断为 “unhealthy” 从而触发重启。
3. Liveness/Readiness probe 的配置非常激进（initialDelay=0、timeout=1s），Photoprism 启动可能需要更长时间，短 probe 会把正在启动的进程判定为不可用并重启 Pod，从而导致 CrashLoopBackOff。

四、最终解决步骤（可复现的修复动作）
--------------------------------
针对以上问题，给出一组可执行的修复动作（按重要性先后）：

A. 修复 PV/hostPath（若使用 hostPath）
- 在 Node 上创建缺失目录并设置权限（以 root SSH 到节点或在节点上运行）：
  sudo mkdir -p /root/software/k8s/photoprism/volume/originals
  sudo mkdir -p /root/software/k8s/photoprism/volume/storage
  sudo chown -R 1000:1000 /root/software/k8s/photoprism/volume
（注：1000:1000 代表常见非 root 运行用户，根据容器实际运行 UID 调整）

B. 放宽或延迟 Liveness/Readiness 探针（避免过早重启）
- 编辑 StatefulSet，增加探针参数：
  initialDelaySeconds: 60
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 6
示例：
```yaml
livenessProbe:
  httpGet:
    path: /
    port: 2342
  initialDelaySeconds: 60
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 6
```
C. 确认只用单副本与 SQLite（若使用 sqlite）
- SQLite 不适合多个副本共享同一数据库文件：保证 StatefulSet replicas=1，或者改用外部 MySQL/MariaDB（在 Helm values 中设置 database.driver=mysql 并填写 host/user/password）。

D. 交互式验证（用 debug pod 手动运行 photoprism）
- 挂载 PVC 后手动执行：
  /opt/photoprism/bin/photoprism start
观察完整输出，定位是否有权限或文件错误。

E. 以防万一：检查 sqlite 文件是否损坏，备份并允许 photoprism 重建（谨慎）
- 备份：cp /photoprism/storage/photoprism.db /photoprism/storage/photoprism.db.bak

五、Gateway API 与 Higress 的兼容性问题（CRD 安装中遇到的问题）
----------------------------------------------------------------
在尝试安装 Gateway API 的 experimental-install.yaml 时遇到错误：
- 原因：CRD manifest 中包含 apiserver 不支持的新 schema 扩展（例如 x-kubernetes-validations），此外还有 server-exported 字段（status、metadata.creationTimestamp、storedVersions 等），这些在你当前的 Kubernetes Server v1.21.1 上会导致验证失败。
- 解决办法：
  1. 若可能，升级 Kubernetes 控制平面到更高版本（长期推荐）。
  2. 否则需要“清理” manifest：删除 x-kubernetes-validations、status、metadata 中 server 填充字段（creationTimestamp、resourceVersion、uid、managedFields、generation）以及类似的扩展字段，随后再 kubectl apply。
  3. 若集群中已存在旧 CRD 且 status.storedVersions 与新 spec 不一致，则需删除原 CRD（并备份 CR），或修正 spec.versions 使之与 storedVersions 对齐。

本文记录了用过的工具与命令（用于清理 CRD manifest 的示例）
- 使用 yq 删除扩展字段：
  yq eval 'del(.. | .["x-kubernetes-validations"]?)' -i experimental-install.yaml
- 使用 Python 脚本 sanitzation（删除 status 与 metadata 中 server 填充项）
  python3 sanitize_crd.py experimental-install.yaml > experimental-install.sanitized.yaml
- 删除有问题的 CRD（在确认无重要自定义对象后）：
  kubectl delete crd backendtlspolicies.gateway.networking.k8s.io

六、结语与建议
----------------
- 当出现 CrashLoopBackOff 时，先看 describe/Events（通常会直接给出 mount/permission/OOM/Probe 的线索）；logs 与 kubectl logs -p 对定位非常关键。
- 对于使用 hostPath 的 PV，务必在节点上预先创建目录并设置合适权限；对于 NFS，确认 server 可用并允许读写（或只读按 design）。
- 对于使用 CRD 的上游清单（尤其是 gateway-api、istio 等），注意 Kubernetes 版本兼容问题：较老的 apiserver 可能不支持最新 CRD 的 schema 扩展，必要时 sanitize 清单或升级控制平面。
- 保留一份“debug / sanitize” 流程脚本，会大幅提升在不同集群版本之间安装开源 controller/CRD 的效率。

参考链接
---------
- PhotoPrism Troubleshooting: https://docs.photoprism.app/getting-started/troubleshooting/
- Gateway API Releases: https://github.com/kubernetes-sigs/gateway-api/releases
- 关于 CRD schema 扩展（x-kubernetes-validations）与 Kubernetes 兼容性：Kubernetes apiextensions-server 文档

