#!/bin/bash

# ==============================================================================
# 🕵️ AUDIT FINOPS ULTIMATE: EL OJO QUE TODO LO VE
# ==============================================================================
# OBJETIVO: Mapear 1:1 con el script de destrucción V4 y detectar zombies ocultos.
# ALCANCE: Cómputo, Redes, K8s, Storage, IAM, Bases de Datos, Contenedores.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REGION=$(aws configure get region)
CLUSTER_KEYWORD="eks-gitops-dev"

echo -e "${CYAN}🔍 INICIANDO AUDITORÍA PROFUNDA EN REGIÓN: $REGION${NC}"
echo "---------------------------------------------------"

# Función auxiliar para reportar
check_resource() {
    NAME=$1
    COUNT=$2
    DETAILS=$3
    COST_WARN=$4 # Si es "HIGH", avisa de costo
    
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${RED}[FAIL] $NAME encontrados: $COUNT${NC}"
        if [ "$COST_WARN" == "HIGH" ]; then
            echo -e "${YELLOW}       ⚠️  ALERTA DE COSTO ALTO O BLOQUEO CRÍTICO${NC}"
        fi
        echo -e "${RED}       -> IDs: $DETAILS${NC}"
    else
        echo -e "${GREEN}[PASS] $NAME: 0 (Limpio)${NC}"
    fi
}

# ---------------------------------------------------------
# 1. CÓMPUTO & AUTO SCALING
# ---------------------------------------------------------
echo -e "\n--- [COMPUTE LAYER] ---"
INSTANCES=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped,shutting-down" --query "Reservations[*].Instances[*].InstanceId" --output text)
COUNT_INST=$(echo "$INSTANCES" | wc -w)
check_resource "Instancias EC2" $COUNT_INST "$INSTANCES" "HIGH"

ASGS=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$CLUSTER_KEYWORD')].AutoScalingGroupName" --output text)
COUNT_ASG=$(echo "$ASGS" | wc -w)
check_resource "Auto Scaling Groups (Nodos)" $COUNT_ASG "$ASGS"

# ---------------------------------------------------------
# 2. ALMACENAMIENTO & BASES DE DATOS (NUEVO: RDS)
# ---------------------------------------------------------
echo -e "\n--- [DATA LAYER] ---"
VOLS=$(aws ec2 describe-volumes --query "Volumes[*].VolumeId" --output text)
COUNT_VOLS=$(echo "$VOLS" | wc -w)
check_resource "Volúmenes EBS" $COUNT_VOLS "$VOLS" "HIGH"

SNAPS=$(aws ec2 describe-snapshots --owner-ids self --query "Snapshots[?contains(Description, '$CLUSTER_KEYWORD')].SnapshotId" --output text)
COUNT_SNAPS=$(echo "$SNAPS" | wc -w)
check_resource "EBS Snapshots" $COUNT_SNAPS "$SNAPS"

RDS=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output text)
COUNT_RDS=$(echo "$RDS" | wc -w)
check_resource "Instancias RDS (Bases de Datos)" $COUNT_RDS "$RDS" "HIGH"

# ---------------------------------------------------------
# 3. CONTENEDORES (NUEVO: ECR)
# ---------------------------------------------------------
echo -e "\n--- [CONTAINER LAYER] ---"
REPOS=$(aws ecr describe-repositories --query "repositories[*].repositoryName" --output text)
COUNT_REPOS=$(echo "$REPOS" | wc -w)
check_resource "Repositorios ECR" $COUNT_REPOS "$REPOS"

# ---------------------------------------------------------
# 4. REDES PROFUNDAS (NUEVO: ENIs & INTERFACES)
# ---------------------------------------------------------
echo -e "\n--- [NETWORKING LAYER] ---"
VPCS=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=false" --query "Vpcs[*].VpcId" --output text)
COUNT_VPCS=$(echo "$VPCS" | wc -w)
check_resource "VPCs Custom (No Default)" $COUNT_VPCS "$VPCS"

# ENIs: La causa oculta de que no se borren las VPCs
ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPCS" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text 2>/dev/null)
if [ ! -z "$VPCS" ]; then
    COUNT_ENI=$(echo "$ENIS" | wc -w)
    check_resource "Interfaces de Red (ENIs - Bloquean VPC)" $COUNT_ENI "Varios (Vinculados a VPCs existentes)"
else
    echo -e "${GREEN}[PASS] Interfaces de Red (ENIs): 0${NC}"
fi

NATS=$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text)
COUNT_NATS=$(echo "$NATS" | wc -w)
check_resource "NAT Gateways" $COUNT_NATS "$NATS" "HIGH"

EIPS=$(aws ec2 describe-addresses --query "Addresses[*].AllocationId" --output text)
COUNT_EIPS=$(echo "$EIPS" | wc -w)
check_resource "Elastic IPs" $COUNT_EIPS "$EIPS" "HIGH"

ALBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn" --output text)
COUNT_ALBS=$(echo "$ALBS" | wc -w)
check_resource "Load Balancers V2 (ALB/NLB)" $COUNT_ALBS "Ver consola para ARNs" "HIGH"

CLBS=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
COUNT_CLBS=$(echo "$CLBS" | wc -w)
check_resource "Classic Load Balancers (Legacy)" $COUNT_CLBS "$CLBS" "HIGH"

# ---------------------------------------------------------
# 5. KUBERNETES & IAM AVANZADO (NUEVO: OIDC)
# ---------------------------------------------------------
echo -e "\n--- [IDENTITY & K8S] ---"
CLUSTERS=$(aws eks list-clusters --query "clusters" --output text)
COUNT_CLUSTERS=$(echo "$CLUSTERS" | wc -w)
check_resource "Clusters EKS" $COUNT_CLUSTERS "$CLUSTERS" "HIGH"

# Roles Manuales
ROLE_CHECK=$(aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole 2>/dev/null)
if [ $? -eq 0 ]; then 
    echo -e "${RED}[FAIL] Rol IAM Manual: 1 (Existe)${NC}"
else 
    echo -e "${GREEN}[PASS] Rol IAM Manual: 0${NC}"
fi

# OIDC Providers (Huérfanos de EKS)
OIDCS=$(aws iam list-open-id-connect-providers --output text | grep "$CLUSTER_KEYWORD" | awk '{print $4}')
COUNT_OIDC=$(echo "$OIDCS" | wc -w)
check_resource "OIDC Providers (Huérfanos EKS)" $COUNT_OIDC "Ver IAM Console"

# ---------------------------------------------------------
# 6. OBSERVABILIDAD
# ---------------------------------------------------------
echo -e "\n--- [LOGGING] ---"
LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$CLUSTER_KEYWORD')].logGroupName" --output text)
COUNT_LOGS=$(echo "$LOGS" | wc -w)
check_resource "Log Groups (CloudWatch)" $COUNT_LOGS "$LOGS"

echo "---------------------------------------------------"
if [ "$COUNT_INST" -eq 0 ] && [ "$COUNT_VPCS" -eq 0 ] && [ "$COUNT_VOLS" -eq 0 ] && [ "$COUNT_NATS" -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO FINOPS: EXCELENTE. COSTO PROYECTADO: $0${NC}"
else
    echo -e "${RED}❌ ESTADO FINOPS: PENDIENTE. EJECUTA EL SCRIPT 'NUKE V4'${NC}"
fi
echo "---------------------------------------------------"
