# AKS Managed Istio with Gateway API

```powershell
# register preview feature for managed gateway api
az extension add --name aks-preview
az extension update --name aks-preview
az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"

# wait for feature registration to complete
az feature show --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview" --query "properties.state"
```