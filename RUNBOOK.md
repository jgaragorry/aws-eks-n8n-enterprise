# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-2.6.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

Este documento es la **Guía Maestra Única**. Siga el orden estricto para garantizar que los permisos de IAM y la persistencia de datos estén listos antes de levantar la aplicación.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Preparación del Entorno](#fase-0-preparación-del-entorno)
2. [Fase 1: Backend de Estado](#fase-1-backend-de-estado)
3. [Fase 2: Infraestructura de Red (VPC)](#fase-2-infraestructura-de-red-vpc)
4. [Fase 3: Cómputo (Cluster EKS)](#fase-3-cómputo-cluster-eks)
5. [Fase 4: Plataforma (Identidad y Tráfico)](#fase-4-plataforma-identidad-y-tráfico)
6. [Fase 5: Despliegue de Aplicación (n8n)](#fase-5-despliegue-de-aplicación-n8n)
7. [Fase 6: La Prueba de Fuego (Webhook Test)](#fase-6-la-prueba-de-fuego-webhook-test)
8. [Fase 7: Protocolo de Destrucción Forense](#fase-7-protocolo-de-destrucción-forense)

---

## 🛠️ Fase 0: Preparación del Entorno
**Objetivo:** Instalar herramientas de gestión de identidad.
```bash
# Instalación de eksctl (Esencial para OIDC)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Validación
aws sts get-caller-identity
eksctl version
```

---

## 📦 Fase 1: Backend de Estado
**Objetivo:** Crear S3 + DynamoDB para el estado persistente de Terraform.
```bash
./scripts/setup_backend.sh
./scripts/check_backend.sh
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
**Objetivo:** Levantar el Cluster Kubernetes y Worker Nodes.
```bash
cd ../eks
terragrunt apply -auto-approve
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma (Identidad y Tráfico)
**Objetivo:** Vincular K8s con AWS y habilitar el Load Balancer.

### 4.1: Vinculación OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Inyección de Permisos IAM (Evita AccessDenied)
```bash
cd ../../../
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam put-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-name ALBControllerPolicy --policy-document file://iam_policy.json
```

### 4.3: Controladores
```bash
./scripts/setup_alb_controller.sh
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

# ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 🚀 Fase 5: Despliegue de Aplicación (n8n)
**Objetivo:** Levantar Base de Datos y n8n en el orden correcto.

### 5.1: Persistencia (PostgreSQL)
```bash
kubectl apply -f gitops/apps/database.yaml 
# Esperar a que el pod esté Running
kubectl get pods -n n8n-system -w
```

### 5.2: Aplicación n8n
```bash
kubectl apply -f gitops/apps/n8n.yaml
# Si el pod estaba en CrashLoop, reiniciarlo:
kubectl rollout restart deployment n8n -n n8n-system
```

**Validación de URL:**
```bash
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar flujo de tráfico externo al cluster.

### 1. URL
Use el **ADDRESS** obtenido en la Fase 5.

### 2. Configuración en n8n
- **Nodo Webhook:** Método `GET` | Path `/estado` | Respond: "Using 'Respond to Webhook' Node".
- **Nodo Respond to Webhook:** En Response Body pega: `{"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀"}`.

### 3. Test
Abre en el navegador: `http://<ADDRESS-ALB>/webhook-test/estado`

---

## 💀 Fase 7: Protocolo de Destrucción Forense
**Objetivo:** Eliminación total para facturación $0.
```bash
# 1. Limpieza de K8s y Volúmenes
kubectl delete ingress --all -A
kubectl delete pvc --all -A
kubectl delete ns n8n-system

# 2. Infraestructura
cd iac/live/dev/eks && terragrunt destroy -auto-approve
cd ../vpc && terragrunt destroy -auto-approve

# 3. Limpieza de Roles y Backend
./scripts/nuke_zombies.sh
./scripts/nuke_backend_smart.sh
./scripts/audit_finops_ultimate.sh
```

---

## 🏁 Fin del Laboratorio

**Estado Final Esperado:** COSTO AWS = $0.00
