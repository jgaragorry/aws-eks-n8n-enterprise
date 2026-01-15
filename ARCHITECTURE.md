# 🏗️ Documentación de Arquitectura

**Sistema:** n8n Enterprise on AWS EKS
**Patrón:** GitOps con Infraestructura Inmutable

Este documento detalla las decisiones arquitectónicas, el flujo de datos y los componentes de infraestructura que componen la plataforma.

---

## 1. Diagrama de Alto Nivel

La solución sigue una arquitectura de **Hub-and-Spoke** simplificada dentro de una única VPC, priorizando la seguridad y el aislamiento.

```mermaid
graph TB
    subgraph "AWS Cloud (us-east-1)"
        subgraph "VPC (10.0.0.0/16)"
            ALB[Application Load Balancer]
            NAT[NAT Gateway]
            IGW[Internet Gateway]
            
            subgraph "Public Subnets"
                ALB
                NAT
            end
            
            subgraph "Private Subnets"
                EKS_Control[EKS Control Plane]
                Nodes[Worker Nodes (EC2)]
            end
        end
    end

    User -->|HTTPS| ALB
    ALB -->|Tráfico Interno| Nodes
    Nodes -->|Salida a Internet| NAT --> IGW
```

---

## 2. Decisiones de Diseño (ADRs)

### 2.1. Cómputo: EKS (Elastic Kubernetes Service)
* **Decisión:** Usar EKS Managed Node Groups.
* **Por qué:** Reduce la carga operativa de gestionar el plano de control y el parchado de los nodos. Permite escalar n8n horizontalmente según la carga de trabajo.
* **Alternativa descartada:** EC2 puras (demasiada gestión manual) o ECS (menos flexible para herramientas complejas como n8n).

### 2.2. Networking: AWS Load Balancer Controller
* **Decisión:** Utilizar el controlador nativo de AWS para gestionar los Ingress.
* **Por qué:** Crea ALBs reales de AWS automáticamente cuando se define un recurso `Ingress` en Kubernetes. Permite terminación SSL y gestión de certificados (ACM) nativa.

### 2.3. Almacenamiento: EBS Dinámico (CSI Driver)
* **Decisión:** Usar `ebs-csi-driver` para los volúmenes persistentes.
* **Por qué:** n8n requiere persistencia para su base de datos interna (Postgres) y archivos locales. EBS garantiza que los datos sobrevivan al reinicio de un Pod.

### 2.4. Despliegue: GitOps con ArgoCD
* **Decisión:** Modelo "Pull" con ArgoCD.
* **Por qué:** Evita tener credenciales de cluster en CI/CD pipelines externos. ArgoCD vive dentro del cluster, vigila el repo de Git y "tira" (pull) los cambios. Es la fuente única de verdad.

---

## 3. Seguridad

### 3.1. IAM Roles for Service Accounts (IRSA)
En lugar de dar credenciales de AWS a los nodos, usamos IRSA.
* El **ALB Controller** tiene su propio Rol IAM que solo le permite tocar Balanceadores.
* El **EBS Driver** tiene su propio Rol IAM que solo le permite tocar Discos.
* **Beneficio:** Principio de mínimo privilegio. Si un pod se ve comprometido, el atacante tiene acceso limitado.

### 3.2. Aislamiento de Red
* Los Nodos de trabajo (donde corre n8n) están en **Subnets Privadas**. No tienen IP pública directa.
* Toda la salida a internet es a través de **NAT Gateway**.
* Toda la entrada es a través del **ALB** (en Subnet Pública).

---

## 4. Stack Tecnológico

| Componente | Tecnología | Uso |
| :--- | :--- | :--- |
| **IaC** | Terraform & Terragrunt | Provisión de VPC, EKS, IAM. |
| **Orquestador** | Kubernetes 1.29+ | Gestión de contenedores. |
| **CD** | ArgoCD | Sincronización continua. |
| **Ingress** | AWS ALB | Entrada de tráfico HTTP/S. |
| **Database** | Postgres (In-Cluster) | Base de datos de n8n. |
| **App** | n8n (Enterprise Image) | Motor de automatización de flujos. |
