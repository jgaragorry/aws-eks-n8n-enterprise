#!/bin/bash

# ==============================================================================
# 🧼 FORENSIC SG WIPER: LIMPIEZA TOTAL DE REGLAS DE SEGURIDAD
# ==============================================================================
# DIAGNÓSTICO: Bloqueo circular entre Security Groups.
# SOLUCIÓN: Descargar reglas en JSON y revocarlas masivamente antes de borrar.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TARGET_VPC="vpc-075e60c657f4e435a"
REGION=$(aws configure get region)

echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   INICIANDO PROTOCOLO SG WIPER PARA: $TARGET_VPC             ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"

# Verificar si la VPC existe
if ! aws ec2 describe-vpcs --vpc-ids $TARGET_VPC >/dev/null 2>&1; then
    echo -e "${GREEN}✅ ¡La VPC ya no existe! Misión cumplida.${NC}"
    exit 0
fi

# 1. OBTENER TODOS LOS SECURITY GROUPS DE LA VPC
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$TARGET_VPC" --query "SecurityGroups[*].GroupId" --output text)

if [ -z "$SGS" ]; then
    echo "   ✅ No se encontraron Security Groups."
else
    echo -e "${CYAN}🔍 PASO 1: Vaciando Reglas (Ingress/Egress) de ${SGS}...${NC}"
    
    for sg in $SGS; do
        echo -e "\n   ➡️  Procesando Grupo: $sg"
        
        # A. REVOCAR INGRESS (ENTRADA)
        # Truco: Obtenemos el JSON exacto de las reglas y se lo pasamos al comando revoke
        aws ec2 describe-security-groups --group-ids $sg --query "SecurityGroups[0].IpPermissions" > "${sg}_ingress.json"
        # Verificamos si el archivo no es vacío o solo "[]"
        if [ -s "${sg}_ingress.json" ] && [ "$(cat ${sg}_ingress.json)" != "[]" ]; then
            echo "      x Revocando reglas de ENTRADA..."
            aws ec2 revoke-security-group-ingress --group-id $sg --ip-permissions file://"${sg}_ingress.json" >/dev/null 2>&1
        else
            echo "      - Sin reglas de entrada."
        fi
        rm -f "${sg}_ingress.json"

        # B. REVOCAR EGRESS (SALIDA)
        aws ec2 describe-security-groups --group-ids $sg --query "SecurityGroups[0].IpPermissionsEgress" > "${sg}_egress.json"
        if [ -s "${sg}_egress.json" ] && [ "$(cat ${sg}_egress.json)" != "[]" ]; then
            echo "      x Revocando reglas de SALIDA..."
            aws ec2 revoke-security-group-egress --group-id $sg --ip-permissions file://"${sg}_egress.json" >/dev/null 2>&1
        else
            echo "      - Sin reglas de salida."
        fi
        rm -f "${sg}_egress.json"
    done
fi

# 2. ELIMINAR LOS GRUPOS (AHORA QUE ESTÁN VACÍOS)
echo -e "\n${CYAN}🗑️ PASO 2: Eliminando Security Groups Vacíos...${NC}"
# Filtramos el 'default' porque ese no se puede borrar (se borra solo con la VPC)
CUSTOM_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$TARGET_VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

for sg in $CUSTOM_SGS; do
    echo "   - Borrando SG: $sg"
    aws ec2 delete-security-group --group-id $sg
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}     ✅ Eliminado.${NC}"
    else
        echo -e "${RED}     ❌ Falló. (Aún con dependencias?)${NC}"
    fi
done

# 3. GOLPE FINAL A LA VPC
echo -e "\n${RED}💥 PASO 3: Eliminando la VPC...${NC}"
# Re-verificar subnets por si acaso
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$TARGET_VPC" --query "Subnets[*].SubnetId" --output text)
for sub in $SUBNETS; do aws ec2 delete-subnet --subnet-id $sub 2>/dev/null; done

aws ec2 delete-vpc --vpc-id $TARGET_VPC
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ¡VICTORIA TOTAL! LA VPC HA SIDO ELIMINADA.${NC}"
else
    echo -e "${RED}❌ Falló el borrado de la VPC. Revisa los errores.${NC}"
fi
