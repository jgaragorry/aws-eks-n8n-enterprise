#!/bin/bash

# ==============================================================================
# ☢️  FORENSIC NUKE V8: FINAL FUSION (INTEGRAL EDITION) ☢️
# ==============================================================================
# HISTORIAL:
# - Integra lógica de detección de Classic LBs (V5).
# - Integra eliminación manual de EKS/Nodos para saltar error Terragrunt (V7).
# - Integra desconexión forzada de ENIs para desbloquear VPC (V5/V6).
# - Integra barrido de ECR/RDS/Logs (V4).
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
echo -e "${RED}║   INICIANDO PROTOCOLO V8 - LA SOLUCIÓN DEFINITIVA                  ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}ℹ️  ESTRATEGIA: Fuerza Bruta Controlada (AWS CLI Directo)${NC}"
echo "⏳ Tienes 5 segundos..."
sleep 5

# ==============================================================================
# FASE 1: LIMPIEZA LÓGICA (INTENTO SUAVE)
# ==============================================================================
echo -e "\n${CYAN}🧹 [FASE 1] Limpieza Lógica (K8s App Layer)...${NC}"
if aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    # Lanzamos procesos en segundo plano para velocidad
    kubectl delete ingress --all --all-namespaces --timeout=10s 2>/dev/null &
    kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer --timeout=10s 2>/dev/null &
    kubectl delete pvc --all --all-namespaces --timeout=10s 2>/dev/null &
    wait
else
    echo "   ⚠️ Cluster no accesible. Saltando a destrucción física."
fi

# ==============================================================================
# FASE 2: IDENTIDAD Y PERMISOS (IAM)
# ==============================================================================
echo -e "\n${CYAN}🧹 [FASE 2] Eliminando Roles y Políticas Manuales...${NC}"
# Rol del Load Balancer
aws iam detach-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy 2>/dev/null
aws iam delete-role --role-name AmazonEKSLoadBalancerControllerRole 2>/dev/null
# Política
VERSIONS=$(aws iam list-policy-versions --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text 2>/dev/null)
for ver in $VERSIONS; do aws iam delete-policy-version --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy --version-id $ver 2>/dev/null; done
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy 2>/dev/null

# ==============================================================================
# FASE 3: DESTRUCCIÓN DE CÓMPUTO (EL NÚCLEO DURO - BYPASS TERRAGRUNT)
# ==============================================================================
echo -e "\n${RED}💀 [FASE 3] DEMOLICIÓN DE CÓMPUTO (NODOS Y CLUSTER)${NC}"

# 3.1 Eliminación de Node Groups (Bloquean el cluster)
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --query "nodegroups" --output text 2>/dev/null)
if [ ! -z "$NODE_GROUPS" ]; then
    for ng in $NODE_GROUPS; do
        echo "   🔥 Eliminando Node Group: $ng"
        aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $ng
    done
    echo -e "${YELLOW}   ⏳ Esperando 4 minutos para que los Nodos mueran...${NC}"
    sleep 240
fi

# 3.2 Eliminación del Cluster EKS
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.status" --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" != "None" ]; then
    echo "   🔥 Enviando orden de destrucción al Cluster EKS..."
    aws eks delete-cluster --name $CLUSTER_NAME 2>/dev/null
    echo -e "${YELLOW}   ⏳ Esperando 5 minutos a que AWS desmonte el Control Plane...${NC}"
    echo "      (No canceles esto, es el tiempo real de AWS)"
    sleep 300
fi

# ==============================================================================
# FASE 4: BARRIDO DE REDES Y BALANCEADORES (ZOMBIE KILLER)
# ==============================================================================
echo -e "\n${RED}💀 [FASE 4] LIMPIEZA DE REDES Y BALANCEADORES${NC}"

# 4.1 Balanceadores (Todos los tipos)
echo "   - ⚖️  Borrando Balanceadores (ALB/NLB y Classic)..."
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerArn" --output text)
for lb in $LBS; do aws elbv2 delete-load-balancer --load-balancer-arn $lb; echo "     🔥 ALB Borrado."; done

CLBS=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
for clb in $CLBS; do aws elb delete-load-balancer --load-balancer-name $clb; echo "     🔥 Classic LB Borrado."; done

# 4.2 NAT Gateways (Costo Alto)
echo "   - 🧱 Borrando NAT Gateways..."
NATS=$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text)
for nat in $NATS; do aws ec2 delete-nat-gateway --nat-gateway-id $nat; echo "     🔥 NAT Borrado."; done
[ ! -z "$NATS" ] && echo "     ⏳ Esperando 30s..." && sleep 30

# 4.3 VPC y Dependencias (ENIs)
echo "   - 🌐 Buscando VPCs residuales..."
VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared" --query "Vpcs[*].VpcId" --output text)

for VPC_ID in $VPC_IDS; do
    if [ "$VPC_ID" != "None" ] && [ ! -z "$VPC_ID" ]; then
        echo -e "${RED}   🚨 INTENTANDO BORRAR VPC: $VPC_ID${NC}"
        
        # A. Cortar ENIs (Interfaces de Red) - CRÍTICO
        echo "     - 🔪 Cortando ENIs (Desconexión forzada)..."
        ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
        for eni in $ENIS; do
            aws ec2 detach-network-interface --network-interface-id $eni --force 2>/dev/null
            aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null
        done
        
        # B. Borrar IGW
        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
        for igw in $IGWS; do
            aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID 2>/dev/null
            aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null
        done

        # C. Borrar Subnets/SGs
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
        for sub in $SUBNETS; do aws ec2 delete-subnet --subnet-id $sub 2>/dev/null; done

        SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
        for sg in $SGS; do aws ec2 delete-security-group --group-id $sg 2>/dev/null; done

        # D. Golpe Final
        aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null && echo "     ✅ VPC Eliminada."
    fi
done

# ==============================================================================
# FASE 5: BARRIDO FINAL (ECR, RDS, STORAGE)
# ==============================================================================
echo -e "\n${CYAN}💰 [FASE 5] Limpieza de Activos Sueltos (Auditoría V5)${NC}"

# ECR
REPOS=$(aws ecr describe-repositories --query "repositories[*].repositoryName" --output text)
for repo in $REPOS; do aws ecr delete-repository --repository-name $repo --force 2>/dev/null; echo "   📦 ECR borrado: $repo"; done

# RDS
DBS=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output text)
for db in $DBS; do aws rds delete-db-instance --db-instance-identifier $db --skip-final-snapshot --delete-automated-backups 2>/dev/null; echo "   🗄️ RDS borrado: $db"; done

# EIPs
EIPS=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].AllocationId" --output text)
for eip in $EIPS; do aws ec2 release-address --allocation-id $eip; echo "   💸 EIP liberada: $eip"; done

# Discos/Snaps
VOLS=$(aws ec2 describe-volumes --filters Name=status,Values=available --query "Volumes[*].VolumeId" --output text)
for vol in $VOLS; do aws ec2 delete-volume --volume-id $vol; echo "   💾 Disco borrado: $vol"; done

SNAPS=$(aws ec2 describe-snapshots --owner-ids self --query "Snapshots[?contains(Description, '$CLUSTER_NAME')].SnapshotId" --output text)
for snap in $SNAPS; do aws ec2 delete-snapshot --snapshot-id $snap; echo "   📷 Snapshot borrado: $snap"; done

# Logs
LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$CLUSTER_NAME')].logGroupName" --output text)
for lg in $LOGS; do aws logs delete-log-group --log-group-name $lg; echo "   🔥 Log borrado: $lg"; done

echo -e "\n${GREEN}✅ PROTOCOLO V8 FINALIZADO. EJECUTA EL AUDITOR AHORA.${NC}"
