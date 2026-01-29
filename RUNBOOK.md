# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-2.5.5-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

Este documento es la **Guía Maestra de Ejecución**. Contiene cada paso necesario para levantar, configurar, probar y destruir la infraestructura, garantizando el **Cero Absoluto** en costos al finalizar.

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
**Objetivo:** Asegurar herramientas de gestión de identidad y acceso.
```bash
# Instalación de eksctl (Obligatorio para OIDC)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Validación de identidad AWS
aws sts get-caller-identity
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
**Objetivo:** Configurar VPC, Subnets y NAT Gateways (Ruta Real).
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
**Objetivo:** Crear el puente de confianza entre AWS y Kubernetes.

### 4.1: Vinculación OIDC (Identidad)
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Inyección de Permisos IAM (Preventivo)
**Evita el error 'AccessDenied' inyectando la política antes de la instalación.**
```bash
cd ../../../
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam put-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-name ALBControllerPolicy --policy-document file://iam_policy.json
```

### 4.3: Instalación de ALB Controller y ArgoCD
```bash
./scripts/setup_alb_controller.sh
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 🚀 Fase 5: Despliegue de Aplicación (n8n)
**Objetivo:** Provisionar n8n Enterprise mediante ArgoCD.
```bash
# Archivo validado: n8n.yaml
kubectl apply -f gitops/apps/n8n.yaml
```

**Validación DNS:**
```bash
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar flujo de tráfico externo al cluster.

### 1. URL
Copia el **ADDRESS** del paso anterior.

### 2. Configuración en n8n
- **Nodo Webhook:** Método `GET` | Path `/estado` | Respond: "Using 'Respond to Webhook' Node".
- **Nodo Respond to Webhook:** En Response Body pega: `{"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀"}`.

### 3. Prueba
Abre en el navegador: `http://<ADDRESS-ALB>/webhook-test/estado`

---

## 💀 Fase 7: Protocolo de Destrucción Forense
**Objetivo:** Eliminación total de recursos facturables.

### 7.1 Limpieza de K8s
```bash
kubectl delete ingress --all -A
kubectl delete pvc --all -A
```

### 7.2 Infraestructura Core
```bash
cd iac/live/dev/eks && terragrunt destroy -auto-approve
cd ../vpc && terragrunt destroy -auto-approve
```

### 7.3 Saneamiento IAM v3 (Anti-Conflictos)
```bash
# Ejecutar script de limpieza de roles y políticas residuales
./scripts/nuke_zombies.sh
./scripts/nuke_backend_smart.sh
./scripts/audit_finops_ultimate.sh
```

---

## 🏁 Fin del Laboratorio

**Estado Final Esperado:** COSTO AWS = $0.00
