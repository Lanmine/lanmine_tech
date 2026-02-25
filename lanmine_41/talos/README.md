# Talos Kubernetes Cluster

This directory contains Talos Linux configuration for the Kubernetes cluster.

## Cluster Info

| Node | Role | IP |
|------|------|-----|
| talos-cp-01 | control-plane | 10.0.10.30 |
| talos-worker-01 | worker | 10.0.10.31 |
| talos-worker-02 | worker | 10.0.10.32 |

## Usage

```bash
# Set config paths
export TALOSCONFIG=~/infra/lanmine_tech/talos/talosconfig
export KUBECONFIG=~/infra/lanmine_tech/talos/kubeconfig

# Talos commands
talosctl --nodes 10.0.10.30 --endpoints 10.0.10.30 health
talosctl --nodes 10.0.10.30 --endpoints 10.0.10.30 dashboard

# Kubernetes commands
kubectl get nodes
kubectl get pods -A
```

## Regenerating configs

If you need to regenerate configs (e.g., after key rotation):

```bash
talosctl gen config lanmine-k8s https://10.0.10.30:6443 --output-dir .
```

Then add the network configuration for each node (interface: ens18).

## Files (not committed - contains secrets)

- `controlplane.yaml` - Control plane machine config
- `worker1.yaml` / `worker2.yaml` - Worker machine configs
- `talosconfig` - Talos CLI config
- `kubeconfig` - Kubernetes config
