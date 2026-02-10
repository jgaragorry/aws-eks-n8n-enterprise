# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-5.0.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

**Propósito:** Guía definitiva y secuencial para el despliegue y destrucción de n8n Enterprise. No omita pasos ni altere el orden. Cada comando ha sido validado para garantizar una infraestructura funcional, persistente y una destrucción total segura.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Preparación del Entorno](#fase-0-preparación-del-entorno)
2. [Fase 1: Backend de Estado (Terragrunt)](#fase-1-backend-de-estado)
3. [Fase 2: Infraestructura de Red (VPC)](#fase-2-infraestructura-de-red-vpc)
4. [Fase 3: Cómputo (Cluster EKS)](#fase-3-cómputo-cluster-eks)
5. [Fase 4: Identidad y Seguridad (IRSA)](#fase-4-identidad-y-seguridad-irsa)
6. [Fase 5: Controladores de Plataforma (ALB & ArgoCD)](#fase-5-controladores-de-plataforma-alb--argocd)
7. [Fase 6: Despliegue de Aplicación (n8n + PostgreSQL)](#fase-6-despliegue-de-aplicación-n8n--postgresql)
8. [Fase 7: Configuración de Validación Visual (HTML)](#fase-7-configuración-de-validación-visual-html)
9. [Fase 8: Protocolo de Destrucción Total ($0.00)](#fase-8-protocolo-de-destrucción-total-000)

---

## 🛠️ Fase 0: Preparación del Entorno
```bash
# Instalación de eksctl para gestión de clúster
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verificación de credenciales de administrador AWS
aws sts get-caller-identity
```

---

## 📦 Fase 1: Backend de Estado
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
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Identidad y Seguridad (IRSA)

### 4.1: Activación de OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Registro de Política IAM (ALB)
```bash
cd ~/aws-eks-n8n-enterprise/
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json
```

### 4.3: Inyección de Identidad (Service Account)
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

### 5.1: Instalación AWS Load Balancer Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=eks-gitops-dev --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller
```

### 5.2: Instalación de ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
```

### 5.3: Acceso

**Obtener Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

**Iniciar Túnel:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**URL:** https://localhost:8080 (User: admin)

---

## 🚀 Fase 6: Despliegue de Aplicación (n8n + PostgreSQL)

### 6.1: Creación de Namespace y Base de Datos
```bash
kubectl create namespace n8n-system
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

### 6.2: Motor n8n e Ingress
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

---

## 🎨 Fase 7: Configuración de Validación Visual (HTML)

### 7.1: Configuración en n8n

**Nodo Webhook:**
- Respond: Cambiar a Using Respond to Webhook Node.

**Nodo Respond to Webhook:**
- Respond With: Text.
- Options (Header): Content-Type: text/html.

**Response Body:** Copie y pegue el siguiente código:
```html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <style>
        body {
            background-color: #232f3e; /* Gris Calama AWS */
            color: #ffffff;
            font-family: 'Amazon Ember', Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .card {
            background-color: #1a1a1a; /* Negro profundo */
            padding: 3rem;
            border-radius: 8px;
            border-top: 5px solid #ff9900; /* Naranja AWS */
            text-align: center;
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            max-width: 600px;
        }
        h1 {
            color: #ff9900; /* Ocre AWS */
            font-size: 2.5rem;
            margin-bottom: 1rem;
            text-transform: uppercase;
        }
        p {
            font-size: 1.2rem;
            color: #d5dbdb;
            line-height: 1.6;
        }
        .badge {
            background: #37474f;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9rem;
            color: #00ff00;
            border: 1px solid #00ff00;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="badge">● SISTEMA ONLINE</div>
        <h1>¡HOLA JOSE! 🤖🚀</h1>
        <p>El clúster <strong>EKS Enterprise</strong> está respondiendo correctamente a través del 
           <strong>AWS Application Load Balancer</strong>.</p>
        <p style="color: #ff9900;">Estado: GitOps Sincronizado vía ArgoCD</p>
    </div>
</body>
</html>
```

---

## 💀 Fase 8: Protocolo de Destrucción Total ($0.00)

**IMPORTANTE:** Seguir este orden estrictamente para evitar bloqueos por dependencias de red.

### 8.1: Nuke de Capa Externa (Balanceadores)
```bash
cd ~/aws-eks-n8n-enterprise/scripts
./nuke_loadbalancers.sh
```

### 8.2: Desbloqueo Manual de Identidad (IAM)

Previene el error DeleteConflict desvinculando la política antes de borrar el rol.
```bash
# 1. Obtener el ARN de la política
POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AWSLoadBalancerControllerIAMPolicy`].Arn' --output text)

# 2. Desvincular política del rol
aws iam detach-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-arn $POLICY_ARN

# 3. Eliminar Rol e IAM Policy
aws iam delete-role --role-name AmazonEKSLoadBalancerControllerRole
aws iam delete-policy --policy-arn $POLICY_ARN
```

### 8.3: Destrucción de Cómputo (EKS)
```bash
cd ~/aws-eks-n8n-enterprise/iac/live/dev/eks
terragrunt destroy -auto-approve
```

### 8.4: Desbloqueo Manual y Destrucción de Red (VPC)

Si Terragrunt se queda en "Still destroying", ejecute esto para liberar Interfaces de Red (ENIs).
```bash
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=gitops-platform-dev-vpc" --query 'Vpcs[0].VpcId' --output text)

# Borrar ENIs huérfanas
ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
for eni in $ENIS; do echo "Liberando ENI: $eni"; aws ec2 delete-network-interface --network-interface-id $eni; done

# Destrucción final de la VPC
cd ~/aws-eks-n8n-enterprise/iac/live/dev/vpc
terragrunt destroy -auto-approve
```

### 8.5: Limpieza de Estado y Auditoría FinOps Final
```bash
cd ~/aws-eks-n8n-enterprise/scripts
./nuke_backend_smart.sh
./audit_finops_extreme.sh
```

---

## 📝 Notas Finales

Este documento refleja exactamente la realidad técnica del clúster. Cada fase ha sido validada para garantizar despliegue exitoso y destrucción segura sin costos residuales.
