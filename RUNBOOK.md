# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-4.0.0-blue?style=for-the-badge)
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
5. [Fase 4: Plataforma (Identidad, IAM y Tráfico)](#fase-4-plataforma-identidad-y-tráfico)
6. [Fase 5: Despliegue de Aplicación (GitOps n8n + DB)](#fase-5-despliegue-de-aplicación-n8n)
7. [Fase 6: La Prueba de Fuego (Validación Webhook)](#fase-6-la-prueba-de-fuego-webhook-test)
8. [Fase 7: Protocolo de Destrucción Forense](#fase-7-protocolo-de-destrucción-forense)

---

## 🛠️ Fase 0: Preparación del Entorno
**Objetivo:** Instalar las herramientas necesarias para la gestión del clúster y la autenticación con AWS.

* **eksctl:** Herramienta oficial para gestionar clústeres EKS y proveedores de identidad OIDC.
* **aws-cli:** Interfaz de comandos para interactuar con los servicios de Amazon.

```bash
# Instalación de eksctl para gestión de OIDC e IAM Roles
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# Verificación de identidad para asegurar que tenemos permisos de administrador
aws sts get-caller-identity
```

---

## 📦 Fase 1: Backend de Estado
**Objetivo:** Configurar S3 y DynamoDB para que Terragrunt pueda almacenar el estado de la infraestructura de forma segura y evitar conflictos de bloqueo.

```bash
./scripts/setup_backend.sh
./scripts/check_backend.sh
```

---

## 🌐 Fase 2: Infraestructura de Red (VPC)
**Objetivo:** Crear la red segmentada (VPC) con subredes públicas y privadas, NAT Gateways y tablas de ruteo necesarias para el tráfico del clúster.

```bash
cd iac/live/dev/vpc
terragrunt apply -auto-approve
```

---

## ☸️ Fase 3: Cómputo (Cluster EKS)
**Objetivo:** Desplegar el clúster de Kubernetes (EKS) y los nodos de trabajo donde correrán nuestros contenedores.

```bash
cd ../eks
terragrunt apply -auto-approve

# Actualizar el archivo kubeconfig local para poder comandar el clúster con kubectl
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

---

## 🏗️ Fase 4: Plataforma (Identidad y Tráfico)
**Objetivo:** Establecer una relación de confianza criptográfica entre AWS y Kubernetes para que el controlador pueda gestionar recursos físicos (ALB) sin usar credenciales estáticas.

### 4.1: Activación de la Relación de Confianza (OIDC)
Este paso crea un proveedor de identidad en AWS que permite al clúster EKS hablar con IAM.

```bash
eksctl utils associate-iam-oidc-provider --cluster eks-gitops-dev --approve
```

### 4.2: Definición de Permisos (Política de IAM)
Se registra en AWS la "lista de acciones permitidas" (crear ALB, borrar subredes, etc.) que el controlador necesita.

```bash
cd ../../../../

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

```

### 4.3: Inyección de Identidad (Service Account + IRSA)
Este es el paso donde unimos ambos mundos. Creamos un Service Account en Kubernetes y un Rol de IAM en AWS al mismo tiempo.

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

### 4.4: Monitoreo Visual (ArgoCD)
Una vez asegurada la plataforma, habilitamos el túnel para la gestión de aplicaciones.
1.  **Contraseña Admin:**
    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
    ```
2.  **Túnel:**
```bash
  kubectl port-forward svc/argocd-server -n argocd 8080:443
```
3.  Abra `https://localhost:8080` e ingrese con usuario `admin`.

---

## 🚀 Fase 5: Despliegue de Aplicación (Full GitOps)
**Objetivo:** Desplegar n8n y su base de datos PostgreSQL de forma que ArgoCD las reconozca y gestione por separado.

### 5.1: Base de Datos (PostgreSQL) - Persistencia
**Inyección de configuración validada (User: n8n_user / Pass: StrongPassword123!).**
Este comando utiliza `<<EOF` para garantizar que todo el contenido del manifiesto se escriba correctamente en el archivo local.

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
# Aplicar la base de datos para inicializar el servicio en el clúster
kubectl apply -f gitops/apps/database.yaml
```

### 5.2: Registro en ArgoCD (Doble Visualización)
**IMPORTANTE:** Este paso crea un objeto tipo `Application` dentro de ArgoCD. Esto permite que la base de datos aparezca como una "tarjeta" independiente en el panel visual, facilitando su monitoreo y sincronización.

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
    repoURL: '[https://github.com/jgaragorry/aws-eks-n8n-enterprise.git](https://github.com/jgaragorry/aws-eks-n8n-enterprise.git)'
    targetRevision: HEAD
    path: gitops/apps
    directory:
      include: 'database.yaml'
  destination:
    server: '[https://kubernetes.default.svc](https://kubernetes.default.svc)'
    namespace: n8n-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### 5.3: Despliegue de Motor n8n
```bash
kubectl apply -f gitops/apps/n8n.yaml
# Monitorear la creación del balanceador de carga externo
kubectl get ingress -n n8n-system --watch
```

---

## 🍒 Fase 6: La Prueba de Fuego (Webhook Test)
**Objetivo:** Validar la comunicación entre el balanceador de AWS (ALB), el Pod de n8n y la base de datos PostgreSQL.

### 1. Acceso
Copie el DNS generado en la Fase 5 (columna ADDRESS) y ábralo en su navegador.

### 2. Creación del Workflow de Validación
- Haga clic en **"Create your first workflow"**.
- Añada un nodo **Webhook** (configurado como GET).
- Añada un nodo **Respond to Webhook**. En **"Response Body"**, seleccione JSON y pegue:
```json
  {"mensaje": "¡Hola Jose! Cluster VIVO 🤖🚀", "db_status": "connected", "gitops": "active"}
```

### 3. Ejecución y Validación Real
- Presione **"Execute Workflow"**.
- Copie la **"Test URL"** generada por el nodo Webhook.
- **IMPORTANTE:** El sistema generará una URL con `localhost:5678`. Debe reemplazar esa parte por su **DNS ADDRESS de AWS**.
- Si visualiza el JSON en el navegador, el tráfico fluye por el Ingress y n8n está operando con normalidad.

---

## 💀 Fase 7: Protocolo de Destrucción Forense ($0.00 Garantizado)

**Objetivo:** Limpieza total, atómica y garantizada de recursos para llevar el costo de la cuenta AWS a cero absoluto.

> [!IMPORTANT]
> **Jerarquía de Destrucción:** En AWS, el orden de los factores sí altera el producto. Debemos liberar la red (Capa 7) antes de destruir la infraestructura (Capa 2-3) para evitar "recursos huérfanos" que bloquean el borrado de la VPC.

---

### 1. Despliegue del "Ariete" (Red y Tráfico)
Liberamos los balanceadores de carga y las IPs elásticas. Esto evita que la VPC quede atrapada intentando borrar subredes asociadas a recursos activos.

`./scripts/nuke_loadbalancers.sh`

### 2. Ejecución del Protocolo Atómico
Usamos el orquestador principal. Este script integra la limpieza de identidades (IAM), el cifrado (KMS) y dispara la destrucción secuencial de la infraestructura.

`./scripts/clean_project_v2.sh`

### 3. Eliminación del "Cerebro" (Backend)
Una vez que la infraestructura física ha sido eliminada, procedemos a borrar el rastro del estado de Terraform para eliminar costos de almacenamiento.

`./scripts/nuke_backend_smart.sh`

### 4. Auditoría de Certificación FinOps
No asumimos el éxito, lo certificamos. Este reporte final verifica cada capa de AWS para asegurar que no existan cargos residuales.

`./scripts/audit_finops_extreme.sh`

---

### 📊 Cuadro de Mandos de Finalización

| Componente | Estado Esperado | Script Responsable |
| :--- | :--- | :--- |
| **Balanceadores (ALB/NLB)** | 0 (Limpio) | nuke_loadbalancers.sh |
| **KMS (Customer Managed)** | PendingDeletion | clean_project_v2.sh |
| **IAM Roles & Policies** | 0 (Limpio) | clean_project_v2.sh |
| **VPC / NAT Gateways** | 0 (Limpio) | clean_project_v2.sh |
| **Backend (S3/Dynamo)** | Eliminado | nuke_backend_smart.sh |

**Estado Final Esperado:** COSTO AWS = $0.00 🏁
