#!/bin/bash
# PROTOCOLO DE DESTRUCCIÓN ATÓMICA V8 (ESTADO-ORIENTED)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

GREEN='\e[32m'; BLUE='\e[34m'; YELLOW='\e[33m'; RED='\e[31m'; NC='\e[0m'
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "\n🔥 INICIANDO LIMPIEZA TOTAL (PROTOCOL: TOTAL WIPE)\n"

# --- [3/6] CAPA DE CIFRADO (KMS AGRESIVO) ---
log_info "Escaneando todas las llaves KMS en la región..."
for key in $(aws kms list-keys --query "Keys[*].KeyId" --output text); do
    # Obtenemos el estado y el Manager (para no intentar borrar llaves de AWS)
    KMS_METADATA=$(aws kms describe-key --key-id "$key" --query "KeyMetadata.[KeyState, KeyManager]" --output text)
    STATE=$(echo $KMS_METADATA | awk '{print $1}')
    MANAGER=$(echo $KMS_METADATA | awk '{print $2}')

    # Solo actuamos sobre llaves del cliente (CUSTOMER) que estén habilitadas
    if [ "$STATE" == "Enabled" ] && [ "$MANAGER" == "CUSTOMER" ]; then
        log_warn "Detectada llave activa cobrando: $key. Sentenciando..."
        aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_ok "Llave $key programada para borrado (Costo detenido)."
        fi
    fi
done

# --- RECOLECCIÓN DE RESTOS (EJECUCIÓN DE AUDITORÍA) ---
if [ -f "./scripts/audit_finops_extreme.sh" ]; then
    ./scripts/audit_finops_extreme.sh
fi
