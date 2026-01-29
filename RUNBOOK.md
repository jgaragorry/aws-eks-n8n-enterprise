# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-2.2.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

Este documento es la **Guía Maestra de Ejecución**. Contiene cada paso necesario para levantar, configurar, probar y destruir la arquitectura, garantizando el **Cero Absoluto** en costos al finalizar.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Preparación del Entorno](#fase-0-preparación-del-entorno)
2. [Fase 1: Backend de Estado (La Base)](#fase-1-backend-de-estado-la-base)
3. [Fase 2: Infraestructura de Red (VPC)](#fase-2-infraestructura-de-red-vpc)
4. [Fase 3: Cómputo (Cluster EKS)](#fase-3-cómputo-cluster-eks)
5. [Fase 4: Plataforma GitOps (ArgoCD & ALB)](#fase-4-plataforma-gitops-argocd--alb)
6. [Fase 5: Despliegue de Aplicación (n8n)](#fase-5-despliegue-de-aplicación-n8n)
7. [Fase 6: La Prueba de Fuego (Webhook Test)](#fase-6-la-prueba-de-fuego-webhook-test)
8. [Fase 7: Protocolo de Destrucción Forense (FinOps)](#fase-7-protocolo-de-destrucción-forense-finops)

---

## 🛠️ Fase 0: Preparación del Entorno
**Objetivo:** Asegurar acceso administrativo a la cuenta AWS.
```bash
aws sts get-caller-identity
# Debe devolver tu Account ID correcta.
```

---

## 📦 Fase 1: Backend de Estado (La Base)
**Objetivo:** Crear S3 + DynamoDB para el estado persistente de Terraform.

**Ejecución:**
```bash
./scripts/setup_backend.sh
```

**Validación:**
```bash
./scripts/check_backend.sh
```

---

## 🌐 Fase 2: Infraestructura de Red (VPC)
**Objetivo:** Configurar VPC, Subnets y NAT Gateways.

**Ejecución:**
```bash
cd iac/live/n8n-ent/dev/vpc
terragrunt apply -auto-approve
```

---

## ☸️ Fase 3: Cómputo (Cluster EKS)
**Objetivo:** Levantar el Cluster Kubernetes y Worker Nodes (t3.medium).

**Ejecución:**
```bash
cd ../eks
terragrunt apply -auto-approve
```

**Conexión Crítica:**
```bash
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma GitOps (ArgoCD & ALB)
**Objetivo:** Instalar controladores de tráfico y motor GitOps.

### Paso 4.1: AWS Load Balancer Controller
```bash
cd ../../../..
./scripts/setup_alb_controller.sh
```

### Paso 4.2: ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 🚀 Fase 5: Despliegue de Aplicación (n8n)
**Objetivo:** Provisionar n8n Enterprise mediante ArgoCD.
```bash
kubectl apply -f gitops/apps/n8n-app.yaml
```

**Validación DNS:**
```bash
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar flujo de tráfico externo al cluster.

### 1. Obtención de URL
Ejecuta `kubectl get ingress -n n8n-system` y copia el valor de **ADDRESS**.

Accede a dicha URL en tu navegador.

### 2. Configuración en n8n
- **Nodo Webhook:** Método `GET` | Path `estado` | Respond: "Using 'Respond to Webhook' Node".
- **Nodo Respond to Webhook:** En Response Body pega: `{"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀"}`.

### 3. Ejecución
- Haz clic en **"Execute Workflow"**.
- Abre en el navegador: `http://<TU-ADDRESS-ALB>/webhook-test/estado`.
- **Éxito:** Debes ver el JSON y el workflow en verde.

---

## 💀 Fase 7: Protocolo de Destrucción Forense (FinOps)
**Objetivo:** Eliminación total de recursos facturables.

### 7.1 Limpieza de K8s (ALB y EBS)
```bash
kubectl delete ingress --all -A
kubectl delete pvc --all -A
```

### 7.2 Destrucción de Infraestructura Core
```bash
cd iac/live/n8n-ent/dev/eks && terragrunt destroy -auto-approve
cd ../vpc && terragrunt destroy -auto-approve
```

### 7.3 Extracción de VPC (Fuerza Bruta)
**Uso exclusivo si la VPC queda bloqueada por dependencias residuales.**
```bash
./scripts/surgical_vpc_extraction.sh <VPC_ID_DE_AUDITORIA>
```

### 7.4 Saneamiento de Identidad (IAM v3 - Anti-Conflictos)
**Elimina roles con políticas Managed e Inline que Terraform olvida.**
```bash
HOY=$(date +%Y-%m-%d)
ROLES=$(aws iam list-roles --query "Roles[?starts_with(CreateDate, '$HOY')].RoleName" --output text)

for role in $ROLES; do
    if [[ $role == AWSServiceRoleFor* ]]; then continue; fi
    echo "🛠️ Limpiando rol: $role"
    for policy in $(aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[*].PolicyArn" --output text); do
        aws iam detach-role-policy --role-name $role --policy-arn $policy
    done
    for inline in $(aws iam list-role-policies --role-name $role --query "PolicyNames[]" --output text); do
        aws iam delete-role-policy --role-name $role --policy-name $inline
    done
    aws iam delete-role --role-name $role
done
```

### 7.5 Cierre de Backend y Auditoría Final
```bash
./scripts/nuke_zombies.sh
./scripts/nuke_backend_smart.sh
./scripts/audit_finops_ultimate.sh
# Veredicto esperado: ✅ ESTADO FINOPS: EXCELENTE
```

---

## 🏁 Fin del Laboratorio

**Estado Final Esperado:** COSTO AWS = $0.00
