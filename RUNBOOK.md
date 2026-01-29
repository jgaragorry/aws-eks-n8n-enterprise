# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-2.9.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Gemini AI | **Nivel:** Enterprise Arch

Este documento es la única fuente de verdad. Siga el orden secuencial para garantizar la persistencia de datos y la conectividad externa.

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
# Instalación de eksctl para gestión de OIDC e IAM Roles
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verificación de identidad
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
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma (Identidad y Tráfico)
**Objetivo:** Configurar el controlador de carga y la identidad del clúster.

### 4.1: Vinculación OIDC
```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Inyección de Permisos IAM (Crítico)
**Vital para que el AWS Load Balancer Controller pueda crear el Ingress ADDRESS.**
```bash
cd ../../../
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam put-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-name ALBControllerPolicy --policy-document file://iam_policy.json
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

### 5.2: Despliegue de n8n
```bash
kubectl apply -f gitops/apps/n8n.yaml
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar la comunicación entre el ALB de AWS, el Pod de n8n y la base de datos PostgreSQL.

### 1. Acceso
Copie el DNS generado en la Fase 5 (ADDRESS) y ábralo en su navegador.

### 2. Setup
Complete el registro inicial de n8n.

### 3. Creación del Workflow
- Haga clic en **"Create your first workflow"**.
- Añada el nodo **Webhook**. Configure:
  - **HTTP Method:** GET
  - **Path:** test-conex
  - **Authentication:** None
- En el panel derecho del nodo, cambie **"Respond"** a **"Using 'Respond to Webhook' Node"**.
- Añada el nodo **Respond to Webhook**. En **"Response Body"**, seleccione JSON y pegue:
```json
  {"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀", "db_status": "connected"}
```

### 4. Ejecución
- Presione el botón **"Execute Workflow"**.
- Copie la **"Test URL"** del nodo Webhook.
- **IMPORTANTE:** Reemplace `http://localhost:5678` por su DNS de AWS (ej: `k8s-n8nsyste-...elb.amazonaws.com`).

### 5. Resultado
Si el navegador muestra el JSON, el tráfico fluye perfectamente por todo el cluster.

---

## 💀 Fase 7: Protocolo de Destrucción Forense
**Objetivo:** Limpieza total para evitar cargos residuales.
```bash
kubectl delete ingress --all -A
kubectl delete ns n8n-system
cd iac/live/dev/eks && terragrunt destroy -auto-approve
cd ../vpc && terragrunt destroy -auto-approve
./scripts/nuke_backend_smart.sh
```

---

## 🏁 Fin del Laboratorio

**Estado Final Esperado:** COSTO AWS = $0.00
