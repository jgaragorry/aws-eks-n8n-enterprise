#!/bin/bash
# ==============================================================================
# 🕵️ AUDIT FINOPS EXTREME: REPORTE DE ESTADO $0 (V4 - TOTAL PRECISION)
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

REGION=$(aws configure get region)

echo -e "\n🔍 INICIANDO AUDITORÍA FORENSE EN REGIÓN: $REGION"
echo "---------------------------------------------------"

check_resource() {
    NAME=$1; COUNT=$2; DETAILS=$3
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${RED}[FAIL] $NAME encontrados: $COUNT${NC}"
        [ ! -z "$DETAILS" ] && echo -e "${RED}       -> $DETAILS${NC}"
    else
        echo -e "${GREEN}[PASS] $NAME: 0 (Limpio)${NC}"
    fi
}

# 1. CÓMPUTO
echo -e "\n--- [COMPUTE] ---"
INSTANCES=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].InstanceId" --output text | wc -w)
check_resource "Instancias EC2 Activas" $INSTANCES ""

# 2. ALMACENAMIENTO
echo -e "\n--- [STORAGE] ---"
VOLUMES=$(aws ec2 describe-volumes --query "Volumes[*].VolumeId" --output text | wc -w)
check_resource "Volúmenes EBS Totales" $VOLUMES ""

# 3. REDES
echo -e "\n--- [NETWORKING] ---"
VPCS=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault==\`false\`].VpcId" --output text | wc -w)
check_resource "VPCs Custom" $VPCS ""

NATS=$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text | wc -w)
check_resource "NAT Gateways" $NATS ""

ALBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn" --output text | wc -w)
check_resource "Balanceadores V2" $ALBS ""

# 4. CAPA DE CIFRADO (KMS - Auditoría de Costo Real)
echo -e "\n--- [KMS CHECK] ---"
KMS_KEYS=$(aws kms list-keys --query "Keys[*].KeyId" --output text)
KMS_FAIL_COUNT=0

for key in $KMS_KEYS; do
    KMS_METADATA=$(aws kms describe-key --key-id "$key" --query "KeyMetadata.[KeyState, KeyManager, Description]" --output text)
    STATE=$(echo $KMS_METADATA | awk '{print $1}')
    MANAGER=$(echo $KMS_METADATA | awk '{print $2}')
    # Capturar la descripción completa
    DESC=$(echo $KMS_METADATA | cut -d' ' -f3-)

    if [ "$MANAGER" == "AWS" ]; then
        # Llaves de AWS son GRATIS, no cuentan como residuo de costo
        echo -e "${GREEN}[PASS] Key AWS Managed (Gratis): $key${NC}"
        echo -e "       -> Desc: $DESC"
    else
        # Solo las Customer Managed tienen costo de $1/mes
        if [ "$STATE" == "Enabled" ]; then
            echo -e "${RED}[FAIL] Key CUSTOMER ACTIVA (Costo $): $key${NC}"
            KMS_FAIL_COUNT=$((KMS_FAIL_COUNT + 1))
        else
            echo -e "${GREEN}[PASS] Key CUSTOMER Sentenciada: $key (Sin cobro)${NC}"
        fi
    fi
done

if [ $KMS_FAIL_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}✨ REPORTE FINOPS: Cero gastos detectados en KMS.${NC}"
fi

# 5. IAM
echo -e "\n--- [IAM CHECK] ---"
ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LoadBalancerControllerRole')].RoleName" --output text)
if [ ! -z "$ROLE_NAME" ]; then 
    echo -e "${RED}[FAIL] Rol Manual IAM ($ROLE_NAME) sigue existiendo.${NC}"; 
else 
    echo -e "${GREEN}[PASS] Rol Manual IAM eliminado.${NC}"; 
fi

echo -e "\n---------------------------------------------------"
echo "Fin de la Auditoría."
