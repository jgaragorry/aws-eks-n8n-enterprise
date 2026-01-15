#!/bin/bash
set -e # Detener el script si hay cualquier error

echo "🚀 Iniciando instalación del AWS Load Balancer Controller..."

# Variables Dinámicas (Se auto-detectan, no necesitas editar nada)
CLUSTER_NAME=$(aws eks list-clusters --query "clusters[0]" --output text)
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# Obtener el OIDC ID limpio (cortando la URL)
OIDC_ISSUER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=$(echo $OIDC_ISSUER | awk -F/ '{print $NF}')
ROLE_NAME="AmazonEKSLoadBalancerControllerRole"

echo "📊 Datos detectados:"
echo "   - Cluster: $CLUSTER_NAME"
echo "   - Región:  $REGION"
echo "   - Cuenta:  $ACCOUNT_ID"
echo "   - OIDC ID: $OIDC_ID"

# 1. Política IAM
echo "🔐 Verificando Política IAM..."
if ! aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy >/dev/null 2>&1; then
    curl -s -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam_policy.json
    rm iam_policy.json
    echo "   ✅ Política creada."
else
    echo "   ⏩ La política ya existe."
fi

# 2. Rol IAM y Trust Policy
echo "👤 Configurando Rol IAM..."
cat > trust.json <<JSON
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
                }
            }
        }
    ]
}
JSON

if ! aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust.json
    aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy
    echo "   ✅ Rol creado y adjunto."
else
    echo "   ⏩ El rol ya existe. Actualizando política de confianza..."
    aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://trust.json
fi
rm trust.json

# 3. Instalación Helm
echo "⚓ Desplegando Helm Chart..."
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1
helm repo update >/dev/null 2>&1

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --set region=$REGION \
  --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text) \
  --wait

echo "✅ ¡Instalación del AWS Load Balancer Controller completada exitosamente!"
