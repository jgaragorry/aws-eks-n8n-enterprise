#!/bin/bash

# ==============================================================================
# ☢️  FORENSIC NUKE V5: ULTIMATE EDITION (AUDIT-AWARE) ☢️
# ==============================================================================
# ESTADO: CRÍTICO.
# BASE: Basado en el reporte de auditoría con 13 ENIs y 1 Classic LB detectados.
# ORDEN: Apps -> IAM -> Terragrunt -> Barrido de Redes (Detach+Delete) -> Storage.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CLUSTER_NAME="eks-gitops-dev"
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Recursos Manuales
IAM_ROLE_NAME="AmazonEKSLoadBalancerControllerRole"
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"

echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   INICIANDO PROTOCOLO V5 - RESPUESTA A INCIDENTE DE AUDITORÍA      ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}🎯 OBJETIVOS PRIORITARIOS DETECTADOS:${NC}"
echo -e "   1. Classic Load Balancer (Legacy)"
echo -e "   2. 13 Interfaces de Red (ENIs) - Requiere Forzar Desconexión"
echo -e "   3. NAT Gateway y EIPs (Costos)"
echo "⏳ Tienes 5 segundos para confirmar..."
sleep 5

# ==============================================================================
# FASE 1: DESMANTELAMIENTO DE CAPA DE APLICACIÓN (KUBERNETES)
# ==============================================================================
echo -e "\n${CYAN}🧹 [FASE 1] Limpieza Lógica (Kubernetes)...${NC}"
# Intentamos limpiar suavemente primero para que AWS reciba las señales correctas
if aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    echo "   - 🌐 Ordenando borrado de Ingress (ALB)..."
    kubectl delete ingress --all --all-namespaces --timeout=10s 2>/dev/null &
    
    echo "   - ⚖️  Ordenando borrado de Services (Classic LB)..."
    kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer --timeout=10s 2>/dev/null &
    
    echo "   - 💾 Ordenando borrado de PVCs (EBS)..."
    kubectl delete pvc --all --all-namespaces --timeout=10s 2>/dev/null &
    
    wait
    echo -e "${YELLOW}   ⏳ Esperando 30s para propagación de eventos...${NC}"
    sleep 30
else
    echo "   ⚠️ Cluster no accesible. Se pasará directo a Fuerza Bruta."
fi

# ==============================================================================
# FASE 2: LIMPIEZA DE IDENTIDAD (IAM)
# ==============================================================================
echo -e "\n${CYAN}🧹 [FASE 2] Limpieza de Recursos Manuales (IAM)...${NC}"

echo "   - 👤 Borrando Rol IAM: $IAM_ROLE_NAME"
aws iam detach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/$IAM_POLICY_NAME 2>/dev/null
aws iam delete-role --role-name $IAM_ROLE_NAME 2>/dev/null || echo "     (Rol ya eliminado)"

echo "   - 📜 Borrando Política IAM: $IAM_POLICY_NAME"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/$IAM_POLICY_NAME"
VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text 2>/dev/null)
for ver in $VERSIONS; do aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $ver 2>/dev/null; done
aws iam delete-policy --policy-arn $POLICY_ARN 2>/dev/null || echo "     (Política ya eliminada)"

# ==============================================================================
# FASE 3: DESTRUCCIÓN INFRAESTRUCTURA (TERRAGRUNT)
# ==============================================================================
echo -e "\n${CYAN}🏗️ [FASE 3] Ejecuyendo Terragrunt Destroy...${NC}"
echo "   ℹ️  Esto eliminará el Cluster EKS, Nodos y la VPC base."

if [ -d "iac/live" ]; then
    cd iac/live
    # Ignorar dependencias es clave aquí porque vamos a borrar cosas manualmente después si falla
    terragrunt run-all destroy --terragrunt-non-interactive --terragrunt-ignore-external-dependencies
    cd ../..
else
    echo "   ⚠️ Carpeta iac/live no encontrada."
fi

# ==============================================================================
# FASE 4: PROTOCOLO DE FUERZA BRUTA (REDES Y BALANCEADORES)
# ==============================================================================
echo -e "\n${RED}💀 [FASE 4] BARRIDO DE ZOMBIES (Basado en Auditoría)${NC}"

# 4.1 BALANCEADORES (Causa #1 de ENIs bloqueadas)
echo "   - ⚖️  Borrando Balanceadores Modernos (ALB/NLB)..."
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerArn" --output text)
for lb in $LBS; do
    echo "     🔥 Eliminando ALB: $lb"
    aws elbv2 delete-load-balancer --load-balancer-arn $lb
done

echo "   - 🏛️  Borrando Classic Load Balancers (DETECTADO EN AUDITORÍA)..."
CLBS=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
for clb in $CLBS; do
    echo "     🔥 Eliminando CLB Legacy: $clb"
    aws elb delete-load-balancer --load-balancer-name $clb
done

if [ ! -z "$LBS" ] || [ ! -z "$CLBS" ]; then
    echo -e "${YELLOW}   ⏳ Esperando 20s para que los Balanceadores suelten las ENIs...${NC}"
    sleep 20
fi

# 4.2 VPCS Y ENIS (La parte más crítica)
echo "   - 🌐 Buscando VPCs residuales..."
VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared" --query "Vpcs[*].VpcId" --output text)

for VPC_ID in $VPC_IDS; do
    if [ "$VPC_ID" != "None" ] && [ ! -z "$VPC_ID" ]; then
        echo -e "${RED}   🚨 VPC ACTIVA DETECTADA ($VPC_ID) - INICIANDO CIRUGÍA MAYOR${NC}"

        # A. NAT GATEWAYS (Liberan EIPs y Rutas)
        echo "     - 🧱 Borrando NAT Gateways..."
        NATS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].NatGatewayId" --output text)
        for nat in $NATS; do 
            aws ec2 delete-nat-gateway --nat-gateway-id $nat
            echo "       🔥 NAT Gateway borrado. Esperando..."
        done
        # Esperar a que el NAT muera (estado 'deleted')
        if [ ! -z "$NATS" ]; then
            echo "       ⏳ Esperando 30s a que los NATs se destruyan totalmente..."
            sleep 30
        fi

        # B. INTERFACES DE RED (ENIs) - EL PROBLEMA DE LOS "13 ENIs"
        echo "     - 🔪 Gestionando Interfaces de Red (ENIs)..."
        ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
        for eni in $ENIS; do
            # Paso Clave: Intentar desvincular primero
            aws ec2 detach-network-interface --network-interface-id $eni --force 2>/dev/null
            aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null
        done
        
        # C. INTERNET GATEWAYS
        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
        for igw in $IGWS; do
            aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID 2>/dev/null
            aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null
        done

        # D. SUBNETS Y SECURITY GROUPS
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
        for sub in $SUBNETS; do aws ec2 delete-subnet --subnet-id $sub 2>/dev/null; done

        SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
        for sg in $SGS; do aws ec2 delete-security-group --group-id $sg 2>/dev/null; done

        # E. ELIMINACIÓN FINAL DE VPC
        echo "     - 💥 Eliminando VPC $VPC_ID..."
        aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null && echo "       ✅ VPC Eliminada." || echo "       ❌ Revisa la consola, algo retiene la VPC."
    fi
done

# ==============================================================================
# FASE 5: LIMPIEZA FINAL (REGISTROS Y COSTOS OCULTOS)
# ==============================================================================
echo -e "\n${RED}💰 [FASE 5] Limpieza de Activos Sueltos${NC}"

# ECR y RDS
REPOS=$(aws ecr describe-repositories --query "repositories[*].repositoryName" --output text)
for repo in $REPOS; do aws ecr delete-repository --repository-name $repo --force 2>/dev/null; echo "   📦 ECR borrado: $repo"; done

DBS=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output text)
for db in $DBS; do aws rds delete-db-instance --db-instance-identifier $db --skip-final-snapshot --delete-automated-backups 2>/dev/null; echo "   🗄️ RDS borrado: $db"; done

# Elastic IPs (Muy importante por costo)
EIPS=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].AllocationId" --output text)
for eip in $EIPS; do aws ec2 release-address --allocation-id $eip; echo "   💸 EIP liberada: $eip"; done

# Discos y Snapshots
VOLS=$(aws ec2 describe-volumes --filters Name=status,Values=available --query "Volumes[*].VolumeId" --output text)
for vol in $VOLS; do aws ec2 delete-volume --volume-id $vol; echo "   💾 Disco borrado: $vol"; done

SNAPS=$(aws ec2 describe-snapshots --owner-ids self --query "Snapshots[?contains(Description, '$CLUSTER_NAME')].SnapshotId" --output text)
for snap in $SNAPS; do aws ec2 delete-snapshot --snapshot-id $snap; echo "   📷 Snapshot borrado: $snap"; done

# Logs
LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$CLUSTER_NAME')].logGroupName" --output text)
for lg in $LOGS; do aws logs delete-log-group --log-group-name $lg; echo "   🔥 Log borrado: $lg"; done

echo -e "\n${GREEN}✅ PROTOCOLO V5 FINALIZADO.${NC}"
