# variables
$group = "rg-aks-istio-gateway"
$cluster = "istiogwcluster"
$location = "eastus2"

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

# deploy nginx and create gateway and httproute
kubectl apply -f workload.yaml
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml

# wait for gateway and get external ip
kubectl wait --for=condition=programmed gateways.gateway.networking.k8s.io nginx-gateway
$ingressHost = kubectl get gateways.gateway.networking.k8s.io nginx-gateway -o jsonpath='{.status.addresses[0].value}'

# test the endpoint
curl -s -I "http://$ingressHost/"