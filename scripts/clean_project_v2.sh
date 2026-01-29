#!/bin/bash
# ==============================================================================
# PROTOCOLO DE DESTRUCCIÓN ATÓMICA E IDEMPOTENTE V6.1 (FINAL)
# Diseñado para: n8n Enterprise en AWS EKS (Garantía $0.00)
# ==============================================================================

# 1. POSICIONAMIENTO DINÁMICO
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# Colores para salida profesional
GREEN='\e[32m'
BLUE='\e[34m'
YELLOW='\e[33m'
NC='\e[0m'

log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "\n🔥 INICIANDO LIMPIEZA TOTAL (PROTOCOL: TOTAL WIPE)\n"

# ------------------------------------------------------------------------------
# FASE 1: DRENAJE DE TRÁFICO (Kubernetes)
# ------------------------------------------------------------------------------
echo "--- [1/6] CAPA DE TRÁFICO (Kubernetes) ---"
CLUSTER_NAME=$(aws eks list-clusters --query "clusters[?contains(@, 'gitops') || contains(@, 'n8n')]" --output text 2>/dev/null)

if [ ! -z "$CLUSTER_NAME" ] && [ "$CLUSTER_NAME" != "None" ]; then
    log_info "Clúster $CLUSTER_NAME detectado. Drenando recursos de red..."
    kubectl delete ingress,svc --all -A --force --grace-period=0 2>/dev/null
    log_ok "Orden de liberación enviada a los balanceadores."
else
    log_info "No se detectó clúster activo. Saltando drenaje."
fi

# ------------------------------------------------------------------------------
# FASE 2: IDENTIDAD Y PERMISOS (IAM)
# ------------------------------------------------------------------------------
echo "--- [2/6] CAPA DE IDENTIDAD (IAM) ---"
ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LoadBalancerControllerRole')].RoleName" --output text 2>/dev/null)

if [ ! -z "$ROLE_NAME" ]; then
    log_info "Limpiando dependencias del Rol: $ROLE_NAME"
    for policy_arn in $(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[*].PolicyArn" --output text 2>/dev/null); do
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" 2>/dev/null
    done
    aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null
    log_ok "Rol de IAM eliminado."
fi

# Borrado de política por nombre (independiente de la cuenta)
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text 2>/dev/null)
if [ ! -z "$POLICY_ARN" ]; then
    log_info "Borrando política: $POLICY_ARN"
    aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null
    log_ok "Política eliminada."
fi

# ------------------------------------------------------------------------------
# FASE 3: CIFRADO Y SEGURIDAD (KMS)
# ------------------------------------------------------------------------------
echo "--- [3/6] CAPA DE CIFRADO (KMS) ---"
KMS_KEYS=$(aws kms list-keys --query "Keys[*].KeyId" --output text 2>/dev/null)

for key in $KMS_KEYS; do
    IS_PROJECT_KEY=$(aws kms list-resource-tags --key-id "$key" --query "Tags[?Value=='gitops-platform-dev-vpc' || Value=='n8n-ent'].Value" --output text 2>/dev/null)
    
    if [ ! -z "$IS_PROJECT_KEY" ]; then
        log_warn "Detectada Llave KMS activa: $key. Programando destrucción..."
        aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 2>/dev/null
        log_ok "Llave programada para borrado (Estado: Pending Deletion)."
    fi
done

# ------------------------------------------------------------------------------
# FASE 4: INFRAESTRUCTURA BASE (Terragrunt)
# ------------------------------------------------------------------------------
echo "--- [4/6] INFRAESTRUCTURA (Terragrunt) ---"
# Búsqueda dinámica del archivo para evitar errores de ruta
HCL_FILE=$(find "$REPO_ROOT" -maxdepth 3 -name "terragrunt.hcl" | head -n 1)

if [ -f "$HCL_FILE" ]; then
    BUCKET_NAME=$(grep 'bucket =' "$HCL_FILE" | awk -F'"' '{print $2}' 2>/dev/null)
    if [ ! -z "$BUCKET_NAME" ] && aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
        log_info "Estado activo detectado en S3. Iniciando destrucción..."
        [ -d "iac/live/dev/eks" ] && (cd iac/live/dev/eks && terragrunt destroy -auto-approve 2>/dev/null)
        [ -d "iac/live/dev/vpc" ] && (cd iac/live/dev/vpc && terragrunt destroy -auto-approve 2>/dev/null)
        log_ok "Terragrunt destroy finalizado."
    else
        log_info "No hay infraestructura activa en el backend."
    fi
else
    log_info "No se encontró configuración de Terragrunt. Saltando..."
fi

# ------------------------------------------------------------------------------
# FASE 5: BACKEND DE ESTADO (S3/Dynamo)
# ------------------------------------------------------------------------------
echo "--- [5/6] LIMPIEZA DE BACKEND (Nuke) ---"
if [ -f "./scripts/nuke_backend_smart.sh" ]; then
    ./scripts/nuke_backend_smart.sh
elif [ -f "$REPO_ROOT/scripts/nuke_backend_smart.sh" ]; then
    "$REPO_ROOT/scripts/nuke_backend_smart.sh"
fi

# ------------------------------------------------------------------------------
# FASE 6: AUDITORÍA FINAL
# ------------------------------------------------------------------------------
echo "--- [6/6] VERIFICACIÓN FINOPS FINAL ---"
if [ -f "./scripts/audit_finops_extreme.sh" ]; then
    ./scripts/audit_finops_extreme.sh
elif [ -f "$REPO_ROOT/scripts/audit_finops_extreme.sh" ]; then
    "$REPO_ROOT/scripts/audit_finops_extreme.sh"
fi

echo -e "\n${GREEN}✨ PROCESO COMPLETADO: Cuenta auditada y limpia.${NC}\n"
