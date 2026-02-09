# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-5.0.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

**Propósito:** Este documento sirve como guía definitiva para el despliegue de una infraestructura GitOps escalable. Está diseñado para ser ejecutado de forma secuencial, garantizando que incluso un técnico sin experiencia previa pueda levantar el entorno n8n Enterprise con persistencia de datos y conectividad pública en AWS.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Preparación del Entorno](#fase-0-preparación-del-entorno)
2. [Fase 1: Backend de Estado (Terragrunt)](#fase-1-backend-de-estado)
3. [Fase 2: Infraestructura de Red (VPC)](#fase-2-infraestructura-de-red-vpc)
4. [Fase 3: Cómputo (Cluster EKS)](#fase-3-cómputo-cluster-eks)
5. [Fase 4: Plataforma (Identidad y Seguridad)](#fase-4-plataforma-identidad-y-seguridad)
6. [Fase 5: Tráfico y GitOps (ALB & ArgoCD)](#fase-5-tráfico-y-gitops)
7. [Fase 6: Despliegue de Aplicación (GitOps n8n + DB)](#fase-6-despliegue-de-aplicación-n8n)
8. [Fase 7: La Prueba de Fuego (Validación Webhook)](#fase-7-la-prueba-de-fuego-webhook-test)
9. [Fase 8: Protocolo de Destrucción Forense](#fase-8-protocolo-de-destrucción-forense)

---

## 🛠️ Fase 0: Preparación del Entorno
**Objetivo:** Instalar las herramientas necesarias para la gestión del clúster y la autenticación con AWS.
```bash
# Instalación de eksctl para gestión de OIDC e IAM Roles
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
**Objetivo:** Establecer la confianza (IRSA) para que los Pods gestionen recursos de AWS.

### 4.1: Activación de OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Registro de Política de IAM
```bash
# Asegurarse de estar en la raíz del proyecto para usar el archivo json
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
```

### 4.3: Creación de Service Account (Identidad del Controlador)
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

## 🚦 Fase 5: Tráfico y GitOps (Controladores)
**Objetivo:** Instalar el software que materializa la infraestructura y el despliegue.

### 5.1: Instalación del AWS Load Balancer Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-gitops-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 5.2: Despliegue de ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
```

### 5.3: Acceso a la Consola ArgoCD

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

### 6.1: Preparación del Entorno n8n
```bash
kubectl create namespace n8n-system
```

### 6.2: Despliegue de Base de Datos (PostgreSQL)
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

### 6.3: Despliegue de Motor n8n e Ingress

**Nota:** Hemos incluido `ingressClassName: alb` para asegurar la detección inmediata por parte del controlador.
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

# Verificación de IP Pública
kubectl get ingress -n n8n-system --watch
```

---

### 💡 ¿Qué cambió para ser un Runbook "limpio"?

1. **Inclusión del Namespace:** El `kubectl create namespace n8n-system` ya es un paso formal en la Fase 6.1.
2. **IngressClassName nativo:** En lugar de parchar con `kubectl patch`, el comando `cat` de la Fase 6.3 ya incluye `ingressClassName: alb`. Así, el recurso nace configurado correctamente.
3. **Orden de Helm:** La Fase 5.1 garantiza que el controlador esté listo **antes** de que intentes desplegar aplicaciones.

---

## 🍒 Fase 7: La Prueba de Fuego (Webhook Test)

1. Copie el ADDRESS del Ingress.
2. Cree un flujo en n8n con un nodo Webhook.
3. Reemplace localhost:5678 por el DNS de AWS y valide la respuesta JSON.

---

## 💀 Fase 8: Protocolo de Destrucción Forense
```bash
./scripts/nuke_loadbalancers.sh

./scripts/clean_project_v2.sh

./scripts/nuke_backend_smart.sh

./scripts/audit_finops_extreme.sh
```

---

## 📝 Notas Finales

Este runbook es una guía completa y secuencial para el despliegue de n8n Enterprise en AWS EKS con GitOps mediante ArgoCD. Sigue cada fase en orden para garantizar una implementación exitosa.
