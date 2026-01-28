#!/bin/bash
# Script para obtener la contraseña inicial de ArgoCD
# Uso: ./scripts/get_argocd_pass.sh

echo "---------------------------------------------------"
echo "🔐 Obteniendo contraseña de administrador para ArgoCD..."
echo "---------------------------------------------------"

PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

if [ -z "$PASS" ]; then
    echo "❌ Error: No se pudo encontrar el secreto. ¿ArgoCD está instalado?"
else
    echo "✅ Usuario: admin"
    echo "✅ Password: $PASS"
    echo "---------------------------------------------------"
    echo "💡 Sugerencia: Una vez que entres, puedes borrar este secreto con:"
    echo "kubectl -n argocd delete secret argocd-initial-admin-secret"
fi
