# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-5.0.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

**Propósito:** Este documento es la única fuente de verdad para el despliegue de n8n Enterprise. Está diseñado para ser ejecutado de forma secuencial. No omita ningún paso; cada comando prepara el entorno para el siguiente.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Preparación del Entorno](#fase-0-preparación-del-entorno)
2. [Fase 1: Backend de Estado (Terragrunt)](#fase-1-backend-de-estado)
3. [Fase 2: Infraestructura de Red (VPC)](#fase-2-infraestructura-de-red-vpc)
4. [Fase 3: Cómputo (Cluster EKS)](#fase-3-cómputo-cluster-eks)
5. [Fase 4: Identidad y Seguridad (IRSA)](#fase-4-plataforma-identidad-y-seguridad)
6. [Fase 5: Controladores de Plataforma (ALB & ArgoCD)](#fase-5-controladores-plataforma)
7. [Fase 6: Despliegue de Aplicación (n8n + PostgreSQL)](#fase-6-despliegue-de-aplicación)
8. [Fase 7: Validación Visual (Landing Page AWS)](#fase-7-validación-visual)
9. [Fase 8: Protocolo de Destrucción Total ($0.00)](#fase-8-protocolo-de-destrucción)

---

## 🛠️ Fase 0: Preparación del Entorno
```bash
# Instalación de eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verificación de credenciales AWS
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

# Sincronización de acceso local
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Identidad y Seguridad (IRSA)
**Objetivo:** Permitir que Kubernetes gestione recursos físicos de AWS.

### 4.1: Activación de Proveedor OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Creación de Política de Permisos
```bash
cd ~/aws-eks-n8n-enterprise/
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
```

### 4.3: Creación de Service Account (Vínculo IAM-K8s)
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

## 🚦 Fase 5: Controladores de Plataforma (ALB & ArgoCD)

### 5.1: Instalación de AWS Load Balancer Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-gitops-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 5.2: Instalación de ArgoCD (Modo Server-Side)
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
```

### 5.3: Recuperación de Credenciales y Acceso

**Obtener Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

**Abrir Túnel:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**URL:** https://localhost:8080 (User: admin)

---

## 🚀 Fase 6: Despliegue de Aplicación

### 6.1: Creación de Namespaces
```bash
kubectl create namespace n8n-system
```

### 6.2: Componente: Base de Datos PostgreSQL

**Paso 1: Generar Manifiesto**
```bash
cat <<EOF > gitops/apps/database.yaml
apiVersion: v1
kind: Service
metadata:
  name: n8n-database-postgresql
  namespace: n8n-system
spec:
  ports:
    - port: 5432
  selector:
    app: n8n-postgres
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n-postgres
  namespace: n8n-system
spec:
  selector:
    matchLabels:
      app: n8n-postgres
  template:
    metadata:
      labels:
        app: n8n-postgres
    spec:
      containers:
        - name: postgres
          image: postgres:13
          env:
            - name: POSTGRES_USER
              value: "n8n_user"
            - name: POSTGRES_PASSWORD
              value: "StrongPassword123!"
            - name: POSTGRES_DB
              value: "n8n_db"
          ports:
            - containerPort: 5432
EOF
kubectl apply -f gitops/apps/database.yaml
```

**Paso 2: Registrar en ArgoCD**
```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n-database
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/jgaragorry/aws-eks-n8n-enterprise.git'
    targetRevision: HEAD
    path: gitops/apps
    directory:
      include: 'database.yaml'
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: n8n-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### 6.3: Componente: Motor n8n e Ingress

**Paso 1: Generar Manifiesto (con IngressClassName corregido)**
```bash
cat <<EOF > gitops/apps/n8n.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n-ingress
  namespace: n8n-system
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: n8n
                port:
                  number: 80
EOF
kubectl apply -f gitops/apps/n8n.yaml
```

**Paso 2: Registrar en ArgoCD**
```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n-workflow-engine
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/jgaragorry/aws-eks-n8n-enterprise.git'
    targetRevision: HEAD
    path: gitops/apps
    directory:
      include: 'n8n.yaml'
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: n8n-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

**Paso 3: Obtener URL Pública**
```bash
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 7: Validación Visual (Landing Page AWS)

Ingrese a n8n mediante el DNS obtenido en la Fase 6.

Configure el nodo Respond to Webhook con:

- **Respond With:** Text
- **Headers:** Content-Type: text/html
- **Body:** Pegue el código HTML con el tema oscuro de AWS.

Pruebe la URL: `http://<ALB-DNS>/webhook-test/aws-test`

---

## 💀 Fase 8: Protocolo de Destrucción Total ($0.00)

**ORDEN CRÍTICO:** No altere la secuencia para evitar recursos bloqueados.

**Liberar Red:**
```bash
./scripts/nuke_loadbalancers.sh
```

**Eliminar Cómputo:**
```bash
./scripts/clean_project_v2.sh
```

**Eliminar Estado:**
```bash
./scripts/nuke_backend_smart.sh
```

**Auditar:**
```bash
./scripts/audit_finops_extreme.sh
```

---

## 📝 Notas Finales

Este documento ahora refleja exactamente la realidad técnica de tu clúster. No hay atajos: se crea el namespace antes de la DB, se define la clase `alb` en el Ingress desde el inicio y se separa la creación del manifiesto del registro en ArgoCD para máxima visibilidad.
