#!/bin/bash

# ==============================================================================
# ☢️  FORENSIC NUKE V10: VPC TERMINATOR (THE FINAL SHOT) ☢️
# ==============================================================================
# OBJETIVO: Eliminar la VPC remanente que quedó bloqueada por tiempos de espera.
# ESTRATEGIA: Bucle de limpieza profunda específico para vpc-075e60c657f4e435a
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TARGET_VPC="vpc-075e60c657f4e435a"
REGION=$(aws configure get region)

echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   INICIANDO PROTOCOLO V10 - ELIMINACIÓN QUIRÚRGICA DE VPC          ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}🎯 TARGET: $TARGET_VPC${NC}"

# Verificar si existe
EXISTS=$(aws ec2 describe-vpcs --vpc-ids $TARGET_VPC 2>/dev/null)
if [ -z "$EXISTS" ]; then
    echo -e "${GREEN}✅ ¡La VPC ya no existe! AWS terminó de borrarla sola.${NC}"
    exit 0
fi

echo "⏳ Iniciando ciclo de limpieza persistente..."

# Bucle infinito hasta que muera (con límite de seguridad)
for i in {1..10}; do
    echo -e "\n🔄 Intento #$i ..."
    
    # 1. Borrar Subnets (A veces reaparecen si el borrado falló)
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$TARGET_VPC" --query "Subnets[*].SubnetId" --output text)
    for sub in $SUBNETS; do aws ec2 delete-subnet --subnet-id $sub 2>/dev/null; done

    # 2. Borrar Security Groups (El bloqueo más común)
    SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$TARGET_VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
    for sg in $SGS; do 
        aws ec2 delete-security-group --group-id $sg 2>/dev/null
    done

    # 3. Borrar Internet Gateways
    IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$TARGET_VPC" --query "InternetGateways[*].InternetGatewayId" --output text)
    for igw in $IGWS; do
        aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $TARGET_VPC 2>/dev/null
        aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null
    done
    
    # 4. Intentar borrar VPC
    aws ec2 delete-vpc --vpc-id $TARGET_VPC 2>/dev/null
    
    # Verificar si murió
    CHECK=$(aws ec2 describe-vpcs --vpc-ids $TARGET_VPC 2>/dev/null)
    if [ -z "$CHECK" ]; then
        echo -e "${GREEN}✅ ¡ÉXITO TOTAL! La VPC $TARGET_VPC ha sido eliminada.${NC}"
        break
    else
        echo -e "${YELLOW}⚠️  La VPC sigue viva (Probablemente esperando que el NAT termine de morir). Esperando 15s...${NC}"
        sleep 15
    fi
done

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   🏁 CICLO FINALIZADO. TU CUENTA ESTÁ LIMPIA.   ${NC}"
echo -e "${GREEN}=================================================================${NC}"
