#!/bin/bash

# ==============================================================================
# 🏥 SURGICAL VPC EXTRACTION: OPERACIÓN A CORAZÓN ABIERTO
# ==============================================================================
# OBJETIVO: Eliminar la VPC vpc-075e60c657f4e435a rompiendo dependencias circulares.
# DIFERENCIA: Elimina primero las REGLAS de los Security Groups, luego los Grupos.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TARGET_VPC="vpc-075e60c657f4e435a"
REGION=$(aws configure get region)

echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   INICIANDO CIRUGÍA PARA VPC: $TARGET_VPC                  ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"

# Verificar existencia
if ! aws ec2 describe-vpcs --vpc-ids $TARGET_VPC >/dev/null 2>&1; then
    echo -e "${GREEN}✅ ¡La VPC ya no existe! Misión cumplida.${NC}"
    exit 0
fi

# ---------------------------------------------------------
# PASO 1: LOBOTOMÍA DE SECURITY GROUPS (REVOCAR REGLAS)
# ---------------------------------------------------------
echo -e "\n${CYAN}🔪 PASO 1: Revocando TODAS las reglas de Security Groups...${NC}"
# Obtener todos los SGs de la VPC (incluyendo el default)
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$TARGET_VPC" --query "SecurityGroups[*].GroupId" --output text)

for sg in $SGS; do
    echo "   - Procesando SG: $sg"
    # Revocar Ingress (Entrada)
    aws ec2 revoke-security-group-ingress --group-id $sg --protocol all --source-group $sg >/dev/null 2>&1
    aws ec2 revoke-security-group-ingress --group-id $sg --protocol all --cidr 0.0.0.0/0 >/dev/null 2>&1
    # Revocar Egress (Salida)
    aws ec2 revoke-security-group-egress --group-id $sg --protocol all --cidr 0.0.0.0/0 >/dev/null 2>&1
done
echo "   ✅ Reglas revocadas (Dependencias circulares rotas)."

# ---------------------------------------------------------
# PASO 2: ELIMINACIÓN DE SECURITY GROUPS
# ---------------------------------------------------------
echo -e "\n${CYAN}🗑️ PASO 2: Eliminando Security Groups Custom...${NC}"
# Obtener SGs que NO sean 'default' (el default no se puede borrar hasta borrar la VPC)
CUSTOM_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$TARGET_VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

if [ ! -z "$CUSTOM_SGS" ]; then
    for sg in $CUSTOM_SGS; do
        echo "   - Intentando borrar SG: $sg"
        aws ec2 delete-security-group --group-id $sg
        if [ $? -eq 0 ]; then
            echo "     ✅ Borrado."
        else
            echo -e "${RED}     ❌ Falló. Revisa el error arriba.${NC}"
        fi
    done
else
    echo "   ✅ No hay Security Groups custom."
fi

# ---------------------------------------------------------
# PASO 3: ELIMINACIÓN DE SUBNETS
# ---------------------------------------------------------
echo -e "\n${CYAN}🕸️ PASO 3: Eliminando Subnets...${NC}"
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$TARGET_VPC" --query "Subnets[*].SubnetId" --output text)

if [ ! -z "$SUBNETS" ]; then
    for sub in $SUBNETS; do
        echo "   - Borrando Subnet: $sub"
        aws ec2 delete-subnet --subnet-id $sub
    done
else
    echo "   ✅ No hay Subnets."
fi

# ---------------------------------------------------------
# PASO 4: ELIMINACIÓN DE INTERNET GATEWAYS
# ---------------------------------------------------------
echo -e "\n${CYAN}nW️ PASO 4: Eliminando Internet Gateways...${NC}"
IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$TARGET_VPC" --query "InternetGateways[*].InternetGatewayId" --output text)
for igw in $IGWS; do
    echo "   - Desconectando y borrando IGW: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $TARGET_VPC
    aws ec2 delete-internet-gateway --internet-gateway-id $igw
done

# ---------------------------------------------------------
# PASO 5: ELIMINACIÓN DE ROUTE TABLES (CUSTOM)
# ---------------------------------------------------------
echo -e "\n${CYAN}🗺️ PASO 5: Eliminando Route Tables extra...${NC}"
# Solo podemos borrar las que no son Main
RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$TARGET_VPC" --query "RouteTables[?Associations==null && PropagatingVgws==null].RouteTableId" --output text)
for rt in $RTS; do
    echo "   - Borrando RT: $rt"
    aws ec2 delete-route-table --route-table-id $rt
done

# ---------------------------------------------------------
# PASO 6: GOLPE FINAL
# ---------------------------------------------------------
echo -e "\n${RED}💥 PASO 6: Eliminando la VPC...${NC}"
aws ec2 delete-vpc --vpc-id $TARGET_VPC
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ¡ÉXITO! La VPC $TARGET_VPC ha sido eliminada.${NC}"
else
    echo -e "${RED}❌ Error al borrar la VPC. Lee el mensaje de error de AWS arriba.${NC}"
fi
