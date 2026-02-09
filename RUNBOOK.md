# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-6.0.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

**Propósito:** Guía definitiva para el despliegue de infraestructura GitOps escalable. Ejecución secuencial garantizada para n8n Enterprise con persistencia y conectividad pública en AWS.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Preparación del Entorno](#fase-0-preparación-del-entorno)
2. [Fase 1: Backend de Estado (Terragrunt)](#fase-1-backend-de-estado)
3. [Fase 2: Infraestructura de Red (VPC)](#fase-2-infraestructura-de-red-vpc)
4. [Fase 3: Cómputo (Cluster EKS)](#fase-3-cómputo-cluster-eks)
5. [Fase 4: Plataforma (Identidad y Seguridad IRSA)](#fase-4-plataforma-identidad-y-seguridad)
6. [Fase 5: Controladores (ALB & ArgoCD)](#fase-5-controladores-alb--argocd)
7. [Fase 6: Despliegue de Aplicación (GitOps n8n + DB)](#fase-6-despliegue-de-aplicación-n8n)
8. [Fase 7: La Prueba de Fuego (Validación Visual AWS)](#fase-7-la-prueba-de-fuego-validación-visual)
9. [Fase 8: Protocolo de Destrucción Total ($0.00)](#fase-8-protocolo-de-destrucción-total)

---

## 🛠️ Fase 0: Preparación del Entorno
**Objetivo:** Instalar herramientas necesarias para gestión del clúster y autenticación con AWS.
```bash
# Instalación de eksctl y aws-cli
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# Verificación de identidad
aws sts get-caller-identity
```

---

## 📦 Fase 1: Backend de Estado
**Objetivo:** Configurar S3 y DynamoDB para el estado de Terragrunt.
```bash
./scripts/setup_backend.sh
./scripts/check_backend.sh
```

---

## 🌐 Fase 2: Infraestructura de Red (VPC)
```bash
cd iac/live/dev/vpc
terragrunt apply -auto-approve
```

---

## ☸️ Fase 3: Cómputo (Cluster EKS)
```bash
cd ../eks
terragrunt apply -auto-approve

# Actualizar kubeconfig
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma (Identidad y Seguridad)
**Objetivo:** Vincular IAM con Kubernetes para permisos dinámicos mediante IRSA.

### 4.1: Activación de OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Registro de Política IAM (ALB)
```bash
cd ~/aws-eks-n8n-enterprise/
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
```

### 4.3: Inyección de Identidad (IRSA)
```bash
eksctl create iamserviceaccount \
  --cluster=eks-gitops-dev \
  --region=us-east-1 \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

---

## 🚦 Fase 5: Controladores (ALB & ArgoCD)
**Objetivo:** Instalar software que materializa la infraestructura y el despliegue.

### 5.1: Instalación AWS Load Balancer Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-gitops-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 5.2: Instalación de ArgoCD (Optimizado)
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
```

### 5.3: Credenciales y Acceso

**Obtener Contraseña:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

**Iniciar Túnel:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Acceso:** https://localhost:8080 (Usuario: admin)

---

## 🚀 Fase 6: Despliegue de Aplicación (n8n Enterprise)

### 6.1: Namespace y Base de Datos
```bash
kubectl create namespace n8n-system
kubectl apply -f gitops/apps/database.yaml
```

### 6.2: Registro de App en ArgoCD
```bash
kubectl apply -f gitops/apps/argocd-app-n8n.yaml
```

### 6.3: Despliegue de n8n e Ingress Class
```bash
kubectl apply -f gitops/apps/n8n.yaml
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 7: La Prueba de Fuego (Validación Visual)

**Configurar Webhook:**
1. En n8n, usar Respond to Webhook Node con tipo `text/html`.
2. Body: Pegar el HTML con estilo AWS (Fondo #232f3e, Header #ff9900).
3. Validar: Acceder a `http://<ALB-ADDRESS>/webhook-test/aws-test`.

---

## 💀 Fase 8: Protocolo de Destrucción Total ($0.00)

**⚠️ IMPORTANTE:** El orden es crítico para evitar bloqueos de red por recursos activos.

### 8.1: Nuke de Capa de Aplicación (Tráfico)

Elimina balanceadores y evita que la VPC quede "atrapada" por dependencias de red.
```bash
./scripts/nuke_loadbalancers.sh
```

### 8.2: Nuke de Infraestructura (Cómputo y Red)

Destrucción atómica de EKS, Nodos y VPC.
```bash
./scripts/clean_project_v2.sh
```

### 8.3: Nuke de Estado (Backend)

Elimina el rastro de Terragrunt en S3 y DynamoDB.
```bash
./scripts/nuke_backend_smart.sh
```

### 8.4: Auditoría Final de Costos
```bash
./scripts/audit_finops_extreme.sh
```

---

## 🔐 Notas de Seguridad para el Video

* **Fase 4:** Si repites comandos, los errores `AlreadyExists` son confirmaciones de éxito.
* **Fase 8:** El script `nuke_loadbalancers.sh` es tu mejor amigo; ejecútalo **siempre primero** para que `terragrunt destroy` no falle al intentar borrar la VPC.

---

## 📝 Resumen de Cambios

- ✅ Versión consolidada (6.0.0) con todas las fases integradas
- ✅ Orden secuencial garantizado
- ✅ Instrucciones claras y limpias
- ✅ Notas de seguridad y errores comunes incluidas
- ✅ Protocolo de destrucción optimizado para evitar costos
