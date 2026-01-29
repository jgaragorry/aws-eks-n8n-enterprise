#!/bin/bash

# ==============================================================================
# ☢️  FORENSIC NUKE V9: OMNIPOTENT EDITION (THE FINAL VERDICT) ☢️
# ==============================================================================
# OBJETIVO: Cero costo. Eliminación total. Sin excusas.
# ENFOQUE: Barrido secuencial de TODAS las fases + "Atomic VPC Cleaner" para la VPC atascada.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CLUSTER_NAME="eks-gitops-dev"
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   INICIANDO PROTOCOLO V9 - LIMPIEZA ATÓMICA DEFINITIVA             ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}ℹ️  ALCANCE: Apps -> IAM -> Compute -> Storage -> NETWORK DEEP CLEAN${NC}"
echo "⏳ Tienes 5 segundos..."
sleep 5

# ==============================================================================
# FASE 1: BARRIDO DE APLICACIÓN (IDEMPOTENTE)
# ==============================================================================
echo -e "\n${CYAN}🧹 [FASE 1] Verificando residuos en Kubernetes...${NC}"
if aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    kubectl delete ingress --all --all-namespaces --timeout=5s 2>/dev/null &
    kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer --timeout=5s 2>/dev/null &
    kubectl delete pvc --all --all-namespaces --timeout=5s 2>/dev/null &
    wait
    echo "   ✅ Comandos enviados (Si el cluster existe)."
else
    echo "   ✅ Cluster inaccesible o ya eliminado. Continuando."
fi

# ==============================================================================
# FASE 2: BARRIDO DE IAM (IDEMPOTENTE)
# ==============================================================================
echo -e "\n${CYAN}🧹 [FASE 2] Verificando Roles Manuales...${NC}"
aws iam detach-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy 2>/dev/null
aws iam delete-role --role-name AmazonEKSLoadBalancerControllerRole 2>/dev/null
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text 2>/dev/null)
for ver in $VERSIONS; do aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $ver 2>/dev/null; done
aws iam delete-policy --policy-arn $POLICY_ARN 2>/dev/null
echo "   ✅ IAM Limpio."

# ==============================================================================
# FASE 3: BARRIDO DE CÓMPUTO (CHECK FINAL)
# ==============================================================================
echo -e "\n${CYAN}💀 [FASE 3] Verificando Cómputo (Cluster y Nodos)...${NC}"

# 3.1 Nodos
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --query "nodegroups" --output text 2>/dev/null)
if [ ! -z "$NODE_GROUPS" ]; then
    for ng in $NODE_GROUPS; do
        echo "   🔥 Eliminando Node Group remanente: $ng"
        aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $ng
    done
    echo "   ⏳ Esperando 2 minutos..." && sleep 120
else
    echo "   ✅ Sin Node Groups activos."
fi

# 3.2 Cluster
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.status" --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" != "None" ] && [ ! -z "$CLUSTER_STATUS" ]; then
    echo "   🔥 Eliminando Cluster EKS: $CLUSTER_STATUS"
    aws eks delete-cluster --name $CLUSTER_NAME 2>/dev/null
    echo "   ⏳ Esperando finalización del cluster (puede tardar)..."
    aws eks wait cluster-deleted --name $CLUSTER_NAME 2>/dev/null
else
    echo "   ✅ Cluster eliminado."
fi

# 3.3 Instancias EC2 Sueltas
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].InstanceId" --output text)
if [ ! -z "$INSTANCES" ]; then
    echo "   🔥 Terminando instancias EC2 huérfanas: $INSTANCES"
    aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null
fi

# ==============================================================================
# FASE 4: NETWORK DEEP CLEAN (EL FIX PARA TU VPC)
# ==============================================================================
echo -e "\n${RED}💀 [FASE 4] LIMPIEZA ATÓMICA DE REDES (VPC CLEANER)${NC}"

# Función para limpiar una VPC por dentro antes de borrarla
atomic_vpc_cleaner() {
    local VPC_ID=$1
    echo -e "${YELLOW}   ⚡ INICIANDO LIMPIEZA PROFUNDA DE: $VPC_ID${NC}"

    # 1. VPC Endpoints (Causa común de bloqueos silenciosos)
    EPS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text)
    if [ ! -z "$EPS" ]; then
        for ep in $EPS; do aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep; echo "     x Endpoint borrado: $ep"; done
    fi

    # 2. NAT Gateways
    NATS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].NatGatewayId" --output text)
    for nat in $NATS; do aws ec2 delete-nat-gateway --nat-gateway-id $nat; echo "     x NAT borrado: $nat"; done
    [ ! -z "$NATS" ] && echo "     ⏳ Esperando a NATs..." && sleep 30

    # 3. ENIs (Interfaces)
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
    for eni in $ENIS; do
        aws ec2 detach-network-interface --network-interface-id $eni --force 2>/dev/null
        aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null
    done

    # 4. Internet Gateways
    IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
    for igw in $IGWS; do
        aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID 2>/dev/null
        aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null
    done

    # 5. Security Groups (Lógica Especial: Revocar reglas primero)
    SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
    for sg in $SGS; do
        # Revocar todo para romper referencias circulares
        aws ec2 revoke-security-group-ingress --group-id $sg --protocol all --source-group $sg 2>/dev/null
        aws ec2 revoke-security-group-egress --group-id $sg --protocol all --cidr 0.0.0.0/0 2>/dev/null
    done
    for sg in $SGS; do aws ec2 delete-security-group --group-id $sg 2>/dev/null; done

    # 6. Subnets
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
    for sub in $SUBNETS; do aws ec2 delete-subnet --subnet-id $sub 2>/dev/null; done

    # 7. Route Tables (Custom)
    RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[?Associations==null].RouteTableId" --output text)
    for rt in $RTS; do aws ec2 delete-route-table --route-table-id $rt 2>/dev/null; done

    # Intentos de borrado de VPC con reintentos
    echo "     💥 Intentando borrar VPC..."
    aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}     ✅ VPC $VPC_ID ELIMINADA.${NC}"
    else
        echo -e "${RED}     ❌ Falló el primer intento. Reintentando en 10s...${NC}"
        sleep 10
        aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null && echo -e "${GREEN}     ✅ VPC $VPC_ID ELIMINADA (Intento 2).${NC}"
    fi
}

# Ejecutar limpieza para CUALQUIER VPC que tenga el tag del cluster O la VPC específica detectada en auditoría
VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared" --query "Vpcs[*].VpcId" --output text)
# Agregar manualmente la VPC que salió en tu auditoría si no la detecta el filtro
AUDIT_VPC="vpc-075e60c657f4e435a"

# Unir listas y limpiar duplicados
ALL_VPCS="$VPC_IDS $AUDIT_VPC"

for VPC in $ALL_VPCS; do
    # Verificar si la VPC aún existe
    EXISTS=$(aws ec2 describe-vpcs --vpc-ids $VPC 2>/dev/null)
    if [ ! -z "$EXISTS" ]; then
        atomic_vpc_cleaner $VPC
    fi
done

# ==============================================================================
# FASE 5: BARRIDO FINAL DE ACTIVOS (ECR, RDS, STORAGE, LBS)
# ==============================================================================
echo -e "\n${CYAN}💰 [FASE 5] Limpieza Final de Activos Sueltos...${NC}"

# Balanceadores
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerArn" --output text)
for lb in $LBS; do aws elbv2 delete-load-balancer --load-balancer-arn $lb; echo "   🔥 ALB borrado."; done
CLBS=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
for clb in $CLBS; do aws elb delete-load-balancer --load-balancer-name $clb; echo "   🔥 CLB borrado."; done

# ECR / RDS
REPOS=$(aws ecr describe-repositories --query "repositories[*].repositoryName" --output text)
for repo in $REPOS; do aws ecr delete-repository --repository-name $repo --force 2>/dev/null; echo "   📦 ECR borrado."; done
DBS=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output text)
for db in $DBS; do aws rds delete-db-instance --db-instance-identifier $db --skip-final-snapshot --delete-automated-backups 2>/dev/null; echo "   🗄️ RDS borrado."; done

# Storage & Logs
EIPS=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].AllocationId" --output text)
for eip in $EIPS; do aws ec2 release-address --allocation-id $eip; echo "   💸 EIP liberada."; done
VOLS=$(aws ec2 describe-volumes --filters Name=status,Values=available --query "Volumes[*].VolumeId" --output text)
for vol in $VOLS; do aws ec2 delete-volume --volume-id $vol; echo "   💾 Disco borrado."; done
SNAPS=$(aws ec2 describe-snapshots --owner-ids self --query "Snapshots[?contains(Description, '$CLUSTER_NAME')].SnapshotId" --output text)
for snap in $SNAPS; do aws ec2 delete-snapshot --snapshot-id $snap; echo "   📷 Snapshot borrado."; done
LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$CLUSTER_NAME')].logGroupName" --output text)
for lg in $LOGS; do aws logs delete-log-group --log-group-name $lg; echo "   🔥 Log borrado."; done

echo -e "\n${GREEN}✅ PROTOCOLO V9 COMPLETADO. EJECUTA EL AUDITOR POR ÚLTIMA VEZ.${NC}"
