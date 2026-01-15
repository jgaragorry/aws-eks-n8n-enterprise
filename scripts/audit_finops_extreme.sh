#!/bin/bash

# ==============================================================================
# 🕵️ AUDIT FINOPS EXTREME: REPORTE DE ESTADO $0
# ==============================================================================
# OBJETIVO: Verificar que NO quede ningún recurso facturable.
# MODO: Solo Lectura.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REGION=$(aws configure get region)
CLUSTER_KEYWORD="eks-gitops-dev"

echo -e "\n🔍 INICIANDO AUDITORÍA FORENSE EN REGIÓN: $REGION"
echo "---------------------------------------------------"

check_resource() {
    NAME=$1
    COUNT=$2
    DETAILS=$3
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${RED}[FAIL] $NAME encontrados: $COUNT${NC}"
        echo -e "${RED}       -> $DETAILS${NC}"
    else
        echo -e "${GREEN}[PASS] $NAME: 0 (Limpio)${NC}"
    fi
}

# 1. CÓMPUTO
echo -e "\n--- [COMPUTE] ---"
INSTANCES=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].InstanceId" --output text | wc -w)
check_resource "Instancias EC2 Activas" $INSTANCES "$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].InstanceId" --output text)"

# 2. ALMACENAMIENTO (DISCOS Y SNAPSHOTS)
echo -e "\n--- [STORAGE] ---"
VOLUMES=$(aws ec2 describe-volumes --query "Volumes[*].VolumeId" --output text | wc -w)
check_resource "Volúmenes EBS Totales" $VOLUMES "$(aws ec2 describe-volumes --query "Volumes[*].VolumeId" --output text)"

SNAPS=$(aws ec2 describe-snapshots --owner-ids self --query "Snapshots[*].SnapshotId" --output text | wc -w)
check_resource "Snapshots Totales" $SNAPS "$(aws ec2 describe-snapshots --owner-ids self --query "Snapshots[*].SnapshotId" --output text)"

# 3. REDES (LO MÁS CRÍTICO)
echo -e "\n--- [NETWORKING] ---"
VPCS=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault==\`false\`].VpcId" --output text | wc -w)
check_resource "VPCs Custom" $VPCS "$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault==\`false\`].VpcId" --output text)"

NATS=$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text | wc -w)
check_resource "NAT Gateways ($$$)" $NATS "$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text)"

EIPS=$(aws ec2 describe-addresses --query "Addresses[*].AllocationId" --output text | wc -w)
check_resource "Elastic IPs ($$$)" $EIPS "$(aws ec2 describe-addresses --query "Addresses[*].AllocationId" --output text)"

ALBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn" --output text | wc -w)
check_resource "Balanceadores V2 (ALB/NLB)" $ALBS ""

CLBS=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text | wc -w)
check_resource "Classic Load Balancers" $CLBS ""

# 4. KUBERNETES
echo -e "\n--- [EKS] ---"
CLUSTERS=$(aws eks list-clusters --query "clusters" --output text | wc -w)
check_resource "Clusters EKS" $CLUSTERS "$(aws eks list-clusters --query "clusters" --output text)"

# 5. IAM (ESPECÍFICO)
echo -e "\n--- [IAM CHECK] ---"
ROLE=$(aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole 2>/dev/null)
if [ $? -eq 0 ]; then echo -e "${RED}[FAIL] Rol Manual IAM sigue existiendo.${NC}"; else echo -e "${GREEN}[PASS] Rol Manual IAM eliminado.${NC}"; fi

POLICY=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].PolicyName" --output text)
if [ ! -z "$POLICY" ]; then echo -e "${RED}[FAIL] Política Manual IAM sigue existiendo.${NC}"; else echo -e "${GREEN}[PASS] Política Manual IAM eliminada.${NC}"; fi

echo "---------------------------------------------------"
echo "Fin de la Auditoría."
