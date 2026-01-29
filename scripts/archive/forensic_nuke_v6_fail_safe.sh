#!/bin/bash

# ==============================================================================
# ☢️  FORENSIC NUKE V6: FAIL-SAFE EDITION ☢️
# ==============================================================================
# CORRECCIÓN: Eliminado flag incompatible de Terragrunt.
# MEJORA: Fase 4 ahora incluye destrucción manual de EKS y EC2 si Terragrunt falla.
# OBJETIVO: Matar NAT Gateway, EKS y VPC a toda costa.
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
echo -e "${RED}║   INICIANDO PROTOCOLO V6 (CORREGIDO Y REFORZADO)                   ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo "⏳ Tienes 5 segundos..."
sleep 5

# ==============================================================================
# FASE 1: LIMPIEZA PREVIA (K8S & IAM) - REPASO RÁPIDO
# ==============================================================================
echo -e "\n${YELLOW}🧹 [FASE 1] Repaso de Limpieza Lógica...${NC}"

# Borrado rápido de IAM por si acaso (Idempotente)
aws iam detach-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy 2>/dev/null
aws iam delete-role --role-name AmazonEKSLoadBalancerControllerRole 2>/dev/null
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
aws iam delete-policy --policy-arn $POLICY_ARN 2>/dev/null

# ==============================================================================
# FASE 2: DESTRUCCIÓN INFRAESTRUCTURA (TERRAGRUNT CORREGIDO)
# ==============================================================================
echo -e "\n${CYAN}🏗️ [FASE 2] Ejecuyendo Terragrunt Destroy (Intento 1)...${NC}"

if [ -d "iac/live" ]; then
    cd iac/live
    # CORRECCIÓN: Quitamos --terragrunt-non-interactive y usamos -auto-approve estándar
    # Usamos 'set +e' para que el script NO se detenga si Terragrunt falla. Queremos que siga a la Fase 3.
    set +e
    terragrunt run-all destroy --terragrunt-ignore-external-dependencies -auto-approve
    TG_EXIT_CODE=$?
    set -e
    cd ../..
    
    if [ $TG_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Terragrunt terminó exitosamente.${NC}"
    else
        echo -e "${RED}❌ Terragrunt falló o quedó incompleto. ACTIVANDO PROTOCOLO MANUAL.${NC}"
    fi
else
    echo "   ⚠️ Carpeta iac/live no encontrada."
fi

# ==============================================================================
# FASE 3: PROTOCOLO MANUAL DE EMERGENCIA (AWS CLI)
# ==============================================================================
echo -e "\n${RED}💀 [FASE 3] DEMOLICIÓN MANUAL DE ACTIVOS COSTOSOS${NC}"
echo "   ℹ️  Esta fase se ejecuta para asegurar la eliminación aunque Terragrunt falle."

# 3.1 NAT GATEWAYS (El costo más alto ahora mismo)
echo "   - 🧱 Buscando NAT Gateways..."
NATS=$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text)
for nat in $NATS; do 
    echo "     🔥 Borrando NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat
done

# 3.2 INSTANCIAS EC2 (Nodos)
echo "   - 💻 Terminando Instancias EC2 (Nodos)..."
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
if [ ! -z "$INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null
    echo "     🔥 Instancias terminadas: $INSTANCES"
fi

# 3.3 EKS CLUSTER
echo "   - ☸️  Eliminando Cluster EKS..."
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.status" --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" == "ACTIVE" ] || [ "$CLUSTER_STATUS" == "UPDATING" ]; then
    aws eks delete-cluster --name $CLUSTER_NAME
    echo "     🔥 Orden de eliminación enviada al Cluster. Esto tardará unos minutos."
else
    echo "     ✅ Cluster no encontrado o ya eliminándose."
fi

# 3.4 LOAD BALANCERS (Repaso final)
echo "   - ⚖️  Repaso de Balanceadores..."
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerArn" --output text)
for lb in $LBS; do aws elbv2 delete-load-balancer --load-balancer-arn $lb; done
CLBS=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
for clb in $CLBS; do aws elb delete-load-balancer --load-balancer-name $clb; done

# ==============================================================================
# FASE 4: LIMPIEZA DE REDES (VPC FINAL)
# ==============================================================================
echo -e "\n${RED}💀 [FASE 4] BARRIDO FINAL DE VPC${NC}"
echo "   ⏳ Esperando 2 minutos para que NATs y Nodos terminen de morir..."
sleep 120 

VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared" --query "Vpcs[*].VpcId" --output text)

for VPC_ID in $VPC_IDS; do
    if [ "$VPC_ID" != "None" ] && [ ! -z "$VPC_ID" ]; then
        echo -e "${RED}   🚨 INTENTANDO BORRAR VPC: $VPC_ID${NC}"
        
        # Cortar ENIs (Interfaces de Red)
        ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
        for eni in $ENIS; do
            aws ec2 detach-network-interface --network-interface-id $eni --force 2>/dev/null
            aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null
        done

        # Borrar dependencias de red
        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
        for igw in $IGWS; do
            aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID 2>/dev/null
            aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null
        done

        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
        for sub in $SUBNETS; do aws ec2 delete-subnet --subnet-id $sub 2>/dev/null; done

        SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
        for sg in $SGS; do aws ec2 delete-security-group --group-id $sg 2>/dev/null; done

        # Intento final
        aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null && echo "     ✅ VPC Eliminada Exitosamente." || echo "     ⚠️ VPC aún retenida (Probablemente el NAT Gateway sigue borrándose. Ejecuta el script de nuevo en 5 min)."
    fi
done

# ==============================================================================
# FASE 5: LIMPIEZA DE ACTIVOS SUELTOS (EIPs, Discos)
# ==============================================================================
echo -e "\n${CYAN}💰 [FASE 5] Limpieza Final de Costos${NC}"
EIPS=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].AllocationId" --output text)
for eip in $EIPS; do aws ec2 release-address --allocation-id $eip; echo "   💸 EIP liberada: $eip"; done

VOLS=$(aws ec2 describe-volumes --filters Name=status,Values=available --query "Volumes[*].VolumeId" --output text)
for vol in $VOLS; do aws ec2 delete-volume --volume-id $vol; echo "   💾 Disco borrado: $vol"; done

LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$CLUSTER_NAME')].logGroupName" --output text)
for lg in $LOGS; do aws logs delete-log-group --log-group-name $lg; echo "   🔥 Log borrado: $lg"; done

echo -e "\n${GREEN}✅ PROTOCOLO V6 FINALIZADO. VERIFICA CON EL AUDITOR.${NC}"
