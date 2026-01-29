# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-2.7.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

Este documento es la **Guía Maestra Única**. El orden de ejecución es atómico: cualquier salto en la configuración de IAM o en la secuencia de la base de datos resultará en fallos de despliegue.

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
**Objetivo:** Instalar herramientas de gestión de clúster e identidad.
```bash
# Instalación de eksctl (Esencial para OIDC e IAM Roles for Service Accounts)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Validación de acceso a AWS
aws sts get-caller-identity
```

---

## 📦 Fase 1: Backend de Estado
**Objetivo:** S3 y DynamoDB para persistencia de Terragrunt.
```bash
./scripts/setup_backend.sh
./scripts/check_backend.sh
```

---

## 🌐 Fase 2: Infraestructura de Red (VPC)
**Objetivo:** Desplegar la red segmentada en AWS.
```bash
cd iac/live/dev/vpc
terragrunt apply -auto-approve
```

---

## ☸️ Fase 3: Cómputo (Cluster EKS)
**Objetivo:** Levantar el plano de control y nodos de trabajo.
```bash
cd ../eks
terragrunt apply -auto-approve

# Actualizar Kubeconfig para acceso local
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma (Identidad y Tráfico)
**Objetivo:** Configurar el controlador de carga y la identidad del clúster.

### 4.1: Vinculación OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Inyección de Permisos IAM (Solución AccessDenied)
**Vital para que el AWS Load Balancer Controller pueda crear el Ingress ADDRESS.**
```bash
cd ../../../
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam put-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-name ALBControllerPolicy --policy-document file://iam_policy.json
```

### 4.3: Despliegue de Controladores
```bash
./scripts/setup_alb_controller.sh
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

# Instalación de ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 🚀 Fase 5: Despliegue de Aplicación (n8n)
**Objetivo:** Levantar n8n con persistencia PostgreSQL sincronizada.

### 5.1: Base de Datos (PostgreSQL)
**Inyección de configuración validada (User: n8n_user / Pass: StrongPassword123!).**
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

### 5.2: Motor n8n y Validación de ADDRESS
```bash
kubectl apply -f gitops/apps/n8n.yaml

# Monitorear hasta obtener DNS del ALB
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar flujo de tráfico externo al cluster.

### 1. URL
Navegar al **ADDRESS** obtenido en la Fase 5.

### 2. Flujo
Crear un Webhook (GET) -> Respond to Webhook.

### 3. Respuesta
JSON: `{"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀"}`

### 4. Verificación
Ejecutar el túnel y validar respuesta exitosa.

---

## 💀 Fase 7: Protocolo de Destrucción Forense
**Objetivo:** Limpieza total para evitar cargos residuales.
```bash
# 1. Limpiar recursos K8s
kubectl delete ingress --all -A
kubectl delete pvc --all -A
kubectl delete ns n8n-system

# 2. Destruir infraestructura
cd iac/live/dev/eks && terragrunt destroy -auto-approve
cd ../vpc && terragrunt destroy -auto-approve

# 3. Limpieza final de backend y roles
./scripts/nuke_zombies.sh
./scripts/nuke_backend_smart.sh
```

---

## 🏁 Fin del Laboratorio

**Estado Final Esperado:** COSTO AWS = $0.00
