# AKS Managed Istio with Gateway API

This project deploys an AKS cluster with the Istio service mesh add-on and the Kubernetes Gateway API, exposing a simple nginx workload through an Istio-managed ingress gateway.

## Prerequisites

- Azure CLI with the `aks-preview` extension (`>= 19.0.0b4`)
- `kubectl`
- PowerShell

```powershell
# register preview feature for managed gateway api
az extension add --name aks-preview
az extension update --name aks-preview
az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"

# wait for feature registration to complete
az feature show --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview" --query "properties.state"
```

## Files

| File | Description |
|---|---|
| `setup.ps1` | Provisions the Azure infrastructure and applies all Kubernetes manifests |
| `workload.yaml` | nginx `Deployment` and `ClusterIP` `Service` |
| `gateway.yaml` | Kubernetes `Gateway` resource backed by Istio |
| `httproute.yaml` | `HTTPRoute` that routes all traffic to the nginx service |

## Deployment

```powershell
./setup.ps1
```

The script will:

1. Create a resource group `rg-aks-istio-gateway` in `eastus2`
2. Create a 2-node AKS cluster with `--enable-azure-service-mesh` and `--enable-gateway-api`
3. Apply the nginx, Gateway, and HTTPRoute manifests
4. Wait for the Gateway to be programmed and print the external IP
5. Send a test `curl` request to verify the deployment

## How Istio Gateway API Works

### Background

The [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) is the successor to the `Ingress` resource. It provides a richer, more expressive model for managing ingress traffic, with clear separation of concerns between infrastructure operators and application developers. Istio implements the Gateway API spec, meaning you can use standard Gateway API resources to control Istio's ingress behavior rather than Istio-specific CRDs.

On AKS, this is enabled through the **Managed Gateway API Installation**, which installs the Gateway API CRDs in a fully supported mode and integrates them with the Istio add-on (revision `asm-1-26` or later).

### Resource Model

The Gateway API splits ingress configuration across three distinct resource types:

```
[ GatewayClass ]  ← defines the controller implementation (e.g. istio)
      |
  [ Gateway ]     ← defines the listener (port, protocol, allowed routes)
      |
 [ HTTPRoute ]    ← defines routing rules (paths, headers, backends)
```

#### GatewayClass

The `GatewayClass` named `istio` is automatically installed by the Istio add-on. It tells the Gateway API that any `Gateway` referencing it should be managed and programmed by Istio's control plane. You do not need to create this resource yourself.

#### Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: nginx-gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
```

When this resource is applied, Istio's control plane (running in the `aks-istio-system` namespace) detects it and uses the **automated deployment model** to automatically provision:

- A `Deployment` for the Envoy-based gateway pods (`nginx-gateway-istio`)
- A `LoadBalancer` `Service` that receives the external IP (`nginx-gateway-istio`)
- A `HorizontalPodAutoscaler` (min 2, max 5 replicas by default)
- A `PodDisruptionBudget` (min 1 available)

This means you do not need to manually manage gateway infrastructure — Istio handles it entirely based on the `Gateway` spec.

`allowedRoutes.namespaces.from: Same` restricts which namespaces can attach `HTTPRoute` resources to this gateway, in this case only the `default` namespace.

#### HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http
  namespace: default
spec:
  parentRefs:
  - name: nginx-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: nginx
      port: 80
```

The `HTTPRoute` attaches to the `Gateway` via `parentRefs` and defines the routing logic. In this deployment:

- No `hostnames` field is set, so the route accepts requests from **any domain**
- All paths (`/` prefix) are forwarded to the `nginx` `Service` on port 80

Istio translates this `HTTPRoute` into Envoy proxy configuration and pushes it to the gateway pods via xDS (the Envoy discovery service).

### Traffic Flow

```
Internet
   │
   ▼
Azure Load Balancer  (provisioned automatically by the Gateway resource)
   │
   ▼
Envoy Gateway Pods  (nginx-gateway-istio, managed by Istio)
   │   ← HTTPRoute rules applied here by Istio control plane
   ▼
nginx ClusterIP Service
   │
   ▼
nginx Pod
```

### Automated vs Manual Deployment Model

This project uses the **automated deployment model**, where Istio creates and manages the gateway `Deployment` and `Service` on your behalf. The alternative **manual deployment model** requires you to pre-create the gateway infrastructure yourself and is typically used for egress scenarios or when more control over the gateway pods is needed.

### ConfigMap Customization

The default resource settings for all Istio-managed gateways are stored in the `istio-gateway-class-defaults` ConfigMap in the `aks-istio-system` namespace. You can inspect or edit them:

```powershell
kubectl get configmap istio-gateway-class-defaults -n aks-istio-system -o yaml
kubectl edit configmap istio-gateway-class-defaults -n aks-istio-system
```

Settings such as HPA min/max replicas and PDB availability can be tuned here, or overridden per-gateway by attaching a dedicated ConfigMap to a specific `Gateway` resource via `spec.infrastructure.parametersRef`.

## References

- [AKS Istio Gateway API documentation](https://learn.microsoft.com/en-us/azure/aks/istio-gateway-api)
- [AKS Managed Gateway API Installation](https://learn.microsoft.com/en-us/azure/aks/managed-gateway-api)
- [Kubernetes Gateway API specification](https://gateway-api.sigs.k8s.io/)
- [Istio Gateway API documentation](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)