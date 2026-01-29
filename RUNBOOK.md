# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-2.5.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

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
**Objetivo:** Garantizar que el entorno local tiene las herramientas para gestionar la nube.

### Instalación de eksctl
**¿Para qué sirve?** Es la herramienta oficial para gestionar clusters EKS. En este lab es **obligatoria** para crear el proveedor OIDC, que permite que los pods de Kubernetes asuman roles de IAM de AWS (necesario para el Load Balancer).
```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
# Verificar instalación:
eksctl version
```

---

## 📦 Fase 1: Backend de Estado (La Base)
**Objetivo:** Crear S3 + DynamoDB para el estado persistente de Terraform.
```bash
./scripts/setup_backend.sh
```

---

## 🌐 Fase 2: Infraestructura de Red (VPC)
**Objetivo:** Configurar VPC, Subnets y NAT Gateways.
```bash
cd iac/live/dev/vpc
terragrunt apply -auto-approve
```

---

## ☸️ Fase 3: Cómputo (Cluster EKS)
**Objetivo:** Levantar el Cluster Kubernetes y Worker Nodes (t3.medium).
```bash
cd ../eks
terragrunt apply -auto-approve
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma GitOps (ArgoCD & ALB)
**Objetivo:** Configurar la identidad del cluster y los controladores de tráfico.

### 4.1: Vinculación OIDC (Identidad)
**Este paso crea la confianza entre AWS y Kubernetes. Es el que permite que aparezca el ADDRESS en el Ingress.**
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: AWS Load Balancer Controller
```bash
cd ../../../..
./scripts/setup_alb_controller.sh
# Forzar reinicio para asegurar toma de nuevos permisos:
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

### 4.3: ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 🚀 Fase 5: Despliegue de Aplicación (n8n)
**Objetivo:** Provisionar n8n Enterprise mediante el manifiesto GitOps.
```bash
kubectl apply -f gitops/apps/n8n.yaml
```

**Validación de ADDRESS (ALB):**
```bash
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar flujo de tráfico externo al cluster.

### 1. URL
Copia el **ADDRESS** de `kubectl get ingress -n n8n-system`.

### 2. Configuración en n8n
- **Nodo Webhook:** Método `GET` | Path `/estado` | Respond: "Using 'Respond to Webhook' Node".
- **Nodo Respond to Webhook:** En Response Body pega: `{"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀"}`.

### 3. Test
Abre en el navegador: `http://<ADDRESS-ALB>/webhook-test/estado`.

---

## 💀 Fase 7: Protocolo de Destrucción Forense (FinOps)
**Objetivo:** Eliminación total de recursos para evitar cargos.

### 7.1 Limpieza de K8s
```bash
kubectl delete ingress --all -A
kubectl delete pvc --all -A
```

### 7.2 Destrucción de Infraestructura Core
```bash
cd iac/live/dev/eks && terragrunt destroy -auto-approve
cd ../vpc && terragrunt destroy -auto-approve
```

### 7.3 Extracción Quirúrgica de VPC (Si hay bloqueo)
```bash
./scripts/surgical_vpc_extraction.sh <VPC_ID_DE_AUDITORIA>
```

### 7.4 Saneamiento de Identidad (IAM v3)
```bash
HOY=$(date +%Y-%m-%d)
ROLES=$(aws iam list-roles --query "Roles[?starts_with(CreateDate, '$HOY')].RoleName" --output text)

for role in $ROLES; do
    if [[ $role == AWSServiceRoleFor* ]]; then continue; fi
    echo "🛠️ Limpiando rol residual: $role"
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
