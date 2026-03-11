# variables
$group = "rg-aks-istio-gateway"
$cluster = "istiogwcluster"
$location = "eastus2"
$publicIpName = "gw-static-ip"

# create resource group
az group create -n $group -l $location

# create aks cluster with istio addon and managed gateway api enabled (2 nodes)
az aks create -g $group -n $cluster `
  --node-count 2 `
  --enable-azure-service-mesh `
  --enable-gateway-api `
  --generate-ssh-keys

# get credentials
az aks get-credentials -g $group -n $cluster --overwrite-existing

# create static public IP in the AKS node resource group
$nodeResourceGroup = az aks show -g $group -n $cluster --query nodeResourceGroup -o tsv
az network public-ip create -g $nodeResourceGroup -n $publicIpName --sku Standard --allocation-method Static
$publicIpAddress = az network public-ip show -g $nodeResourceGroup -n $publicIpName --query ipAddress -o tsv

# deploy nginx and create gateway and httproute
kubectl apply -f workload.yaml
(Get-Content gateway.yaml -Raw).Replace("__STATIC_IP__", $publicIpAddress) | kubectl apply -f -
kubectl apply -f httproute.yaml

# wait for gateway and get external ip
kubectl wait --for=condition=programmed gateways.gateway.networking.k8s.io nginx-gateway
$ingressHost = kubectl get gateways.gateway.networking.k8s.io nginx-gateway -o jsonpath='{.status.addresses[0].value}'

# test the endpoint
curl -s -I "http://$ingressHost/"