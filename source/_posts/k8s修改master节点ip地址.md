---
title: "实战笔记：修改 Kubernetes Master 节点 IP 地址"
date: 2025-10-23 11:00:00
categories:
  - Kubernetes
  - 运维
tags:
  - Kubernetes
  - Master 节点
  - IP 变更
  - kubeadm
description: "记录一次将 Master 节点 IP 从 43.139.105.42 迁移到 172.16.16.10 的完整过程，覆盖备份、配置替换、证书更新以及常见坑位。"
---

在生产集群中修改 Master 节点 IP 是一项高风险操作。这篇笔记记录了我在单 Master（kubeadm 部署）集群中，将控制平面地址从 `43.139.105.42`（`master.cluster.zlinkcloudtech.com`）迁移到 `172.16.16.10` 的完整过程。

> ⚠️ **强烈建议**：先在测试环境演练，并务必做好 ETCD 与 `/etc/kubernetes` 目录的完整备份，失败时才能快速回滚。

<!-- more -->

---

## 1. 前提检查与备份

```bash
# 备份 /etc/kubernetes 全量配置（含 kubeconfig、证书、静态 Pod 清单）
sudo cp -Rf /etc/kubernetes/ /etc/kubernetes_bak

# 根据自身情况创建 ETCD 快照（略）
```

---

## 2. 替换配置文件中的旧地址

集中处理 Master 节点本地配置以及当前用户的 kubeconfig。

```bash
# 1) 处理 /etc/kubernetes 下所有文件
cd /etc/kubernetes
sudo find . -type f -exec sed -i 's/43.139.105.42/172.16.16.10/g' {} +
sudo find . -type f -exec sed -i 's/master\.cluster\.zlinkcloudtech\.com/172.16.16.10/g' {} +

# 2) 处理 $HOME/.kube 下的缓存与 kubeconfig
cd $HOME/.kube
sudo find . -type f -exec sed -i 's/43.139.105.42/172.16.16.10/g' {} +
sudo find . -type f -exec sed -i 's/master\.cluster\.zlinkcloudtech\.com/172.16.16.10/g' {} +

# 3) 修复 discovery 缓存目录名称
cd $HOME/.kube/cache/discovery
mv master.cluster.zlinkcloudtech.com_6443 172.16.16.10_6443
```

---

## 3. 处理证书 SAN

检查证书是否仍包含旧 IP，尤其是 `apiserver.crt` 与 etcd 相关证书。

```bash
cd /etc/kubernetes/pki
for crt in $(find . -type f -name "*.crt"); do
  echo "==> $crt"
  openssl x509 -in "$crt" -text | grep -A1 'Address'
done
```

输出中可以看到旧 IP `43.139.105.42` 仍在若干证书 SAN 中。

删除受影响证书，让 kubeadm 重新生成：

```bash
sudo rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
sudo rm -f /etc/kubernetes/pki/etcd/peer.crt /etc/kubernetes/pki/etcd/peer.key
sudo rm -f /etc/kubernetes/pki/etcd/server.crt /etc/kubernetes/pki/etcd/server.key
```

重新生成证书（会读取当前 kubeadm 配置）：

```bash
kubeadm init phase certs all
```

> 提示：证书生成过程中，如需平滑过渡，可在 `kubeadm-config` 中同时保留新旧 IP，验证通过后再移除旧值。

---

## 4. 更新 ConfigMap 与服务配置

### 4.1 kubeadm-config

```bash
kubectl -n kube-system edit cm kubeadm-config
# 将 controlPlaneEndpoint 调整为 172.16.16.10:6443
# 确认 apiServer.certSANs 中已包含新 IP
```

### 4.2 kube-proxy 与 cluster-info

```bash
kubectl -n kube-system edit cm kube-proxy
kubectl -n kube-public edit cm cluster-info
```

根据需要检查 `coredns` 等组件配置（本次未修改）。

### 4.3 kubelet systemd 配置

确保 kubelet 启动参数携带新的节点 IP。

```bash
sudo vi /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
# 确认 ExecStart 行含有 --node-ip=172.16.16.10

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

重启后，静态 Pod（apiserver/controller-manager/scheduler）会被 kubelet 自动拉起。

---

## 5. 重启与加入令牌

为防止残余状态，重启 Master 节点：

```bash
sudo reboot
```

开机后，如需 Worker 重新加入，可重新生成 join 命令：

```bash
kubeadm token create --print-join-command
```

---

## 6. Worker 节点跟进（按需执行）

若 Worker 节点的 kubelet 配置中写死了旧 IP，需要同步替换并重启 kubelet。

```bash
sudo sed -i 's/43.139.105.42/172.16.16.10/g' /etc/kubernetes/kubelet.conf
sudo systemctl restart kubelet
```

---

## 7. 验证

```bash
# 核心组件健康
kubectl get pods -n kube-system

# 节点状态
kubectl get nodes -o wide

# 测试跨组件通信
kubectl run pingtest --image=busybox --restart=Never -- ping -c3 kubernetes.default
```

---

## 遇到的问题与提醒

1. **证书未更新**：如果忘记删除旧证书直接运行 `kubeadm init phase certs all`，新 IP 不会写入 SAN，需要先手动删除对应 `crt/key`。
2. **ConfigMap 残留旧地址**：`kube-proxy` 或 `cluster-info` 中未更新会导致发现机制异常，应逐项排查。
3. **kubelet 未携带新 IP**：`--node-ip` 未更新会出现 Node `NotReady`，重启 kubelet 前务必确认 systemd 配置。
4. **备份不可省**：任何环节如操作失误，回滚至 `/etc/kubernetes_bak` 或 ETCD 快照是唯一保险方案。

---

参考文档：
https://www.cnblogs.com/hxlasky/p/19072204
https://blog.csdn.net/easylife206/article/details/126112890
