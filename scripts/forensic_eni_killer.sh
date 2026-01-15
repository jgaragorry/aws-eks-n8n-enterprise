#!/bin/bash

# ==============================================================================
# 💉 FORENSIC ENI KILLER: EXTACCIÓN DE INTERFACES FANTASMA
# ==============================================================================
# DIAGNÓSTICO: Los Security Groups no se borran porque hay ENIs conectadas.
# OBJETIVO: Encontrar esas ENIs, desconectarlas, borrarlas y liberar la VPC.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TARGET_VPC="vpc-075e60c657f4e435a"
REGION=$(aws configure get region)

echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   INICIANDO PROTOCOLO ENI KILLER PARA: $TARGET_VPC           ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"

# 1. BÚSQUEDA DE EVIDENCIA (ENIs)
echo -e "\n${CYAN}🔍 PASO 1: Escaneando Interfaces de Red (ENIs) ocultas...${NC}"
ENI_IDS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$TARGET_VPC" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)

if [ -z "$ENI_IDS" ]; then
    echo -e "${GREEN}   ✅ No se detectaron ENIs visibles. (Qué extraño...)${NC}"
else
    COUNT=$(echo $ENI_IDS | wc -w)
    echo -e "${YELLOW}   ⚠️  ¡DETECTADAS $COUNT INTERFACES DE RED QUE BLOQUEAN TODO!${NC}"
    
    # Mostrar detalles para el forense
    aws ec2 describe-network-interfaces --network-interface-ids $ENI_IDS --query "NetworkInterfaces[*].{ID:NetworkInterfaceId, Desc:Description, Status:Status, Owner:RequesterId}" --output table

    # 2. EJECUCIÓN (DETACH & DELETE)
    echo -e "\n${RED}🔪 PASO 2: Forzando desconexión y eliminación de ENIs...${NC}"
    for eni in $ENI_IDS; do
        echo "   - Atacando ENI: $eni"
        
        # Intentar Detach (Desconectar)
        ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $eni --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text)
        if [ "$ATTACHMENT_ID" != "None" ]; then
            echo "     x Desconectando Attachment: $ATTACHMENT_ID"
            aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force >/dev/null 2>&1
            sleep 2
        fi

        # Intentar Delete
        aws ec2 delete-network-interface --network-interface-id $eni
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}     ✅ ENI Eliminada.${NC}"
        else
            echo -e "${RED}     ❌ Falló eliminación. (Es posible que sea gestionada por AWS, reintentando...)${NC}"
            sleep 5
            aws ec2 delete-network-interface --network-interface-id $eni >/dev/null 2>&1
        fi
    done
fi

# 3. REINTENTO DE SECURITY GROUPS
echo -e "\n${CYAN}🗑️ PASO 3: Reintentando borrar Security Groups...${NC}"
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$TARGET_VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

if [ ! -z "$SGS" ]; then
    for sg in $SGS; do
        echo "   - Borrando SG: $sg"
        aws ec2 delete-security-group --group-id $sg
        if [ $? -eq 0 ]; then echo -e "${GREEN}     ✅ Éxito.${NC}"; else echo -e "${RED}     ❌ Falló (¿Aún tiene ENIs?).${NC}"; fi
    done
else
    echo "   ✅ Ya no quedan SGs custom."
fi

# 4. GOLPE FINAL A LA VPC
echo -e "\n${RED}💥 PASO 4: Eliminando la VPC...${NC}"
aws ec2 delete-vpc --vpc-id $TARGET_VPC
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ¡VICTORIA! LA VPC HA SIDO ELIMINADA.${NC}"
else
    echo -e "${RED}❌ Aún resiste. Ejecuta este script una vez más en 30 segundos.${NC}"
    echo "   (A veces AWS tarda en propagar la eliminación de las ENIs)"
fi
