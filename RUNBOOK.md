# 🚀 RUNBOOK MASTER: Despliegue n8n Enterprise en AWS EKS

![Status](https://img.shields.io/badge/STATUS-PRODUCCIÓN-success?style=for-the-badge&logo=checkmarx)
![Version](https://img.shields.io/badge/VERSION-1.0.0-blue?style=for-the-badge)
![FinOps](https://img.shields.io/badge/FINOPS-CERTIFIED-red?style=for-the-badge&logo=moneygram)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![GitOps](https://img.shields.io/badge/GITOPS-ARGOCD-orange?style=for-the-badge&logo=argo)

**Autor:** Jose Garagorry & Copiloto IA | **Nivel:** Enterprise Arch

Este documento es la **Guía Maestra de Ejecución**. Contiene cada paso necesario para levantar, configurar, probar y destruir la arquitectura. Diseñado para ser ejecutado secuencialmente durante la grabación de la Masterclass.

---

## 📋 Tabla de Contenidos
1.  [Fase 0: Preparación del Entorno](#fase-0)
2.  [Fase 1: Backend de Estado (La Base)](#fase-1)
3.  [Fase 2: Infraestructura de Red (VPC)](#fase-2)
4.  [Fase 3: Cómputo (Cluster EKS)](#fase-3)
5.  [Fase 4: Plataforma GitOps (ArgoCD & Ingress)](#fase-4)
6.  [Fase 5: Despliegue de Aplicación (n8n)](#fase-5)
7.  [Fase 6: LA PRUEBA DE FUEGO (Configuración n8n)](#fase-6) 🍒 *La Guinda del Pastel*
8.  [Fase 7: Protocolo de Destrucción Forense](#fase-7)

---

## <a name="fase-0"></a>🛠️ Fase 0: Preparación del Entorno
**Objetivo:** Asegurar que tenemos las llaves del reino antes de empezar.

**Herramientas Requeridas:**
* `aws cli` (Configurado con Admin Access)
* `terraform` & `terragrunt`
* `kubectl` & `helm`

**Validación Inicial:**
```bash
aws sts get-caller-identity
# Debe devolver tu Account ID correcta.
```

---

## <a name="fase-1"></a>📦 Fase 1: Backend de Estado
**Objetivo:** Crear el almacenamiento seguro para el estado de Terraform (S3 + DynamoDB).
**¿Por qué?** Sin esto, no podemos trabajar en equipo ni asegurar la integridad de la infraestructura.

**Ejecución:**
```bash
./scripts/setup_backend.sh
```

**Validación:**
```bash
./scripts/check_backend.sh
# Debe decir [EXISTE] en verde para S3 y DynamoDB.
```

---

## <a name="fase-2"></a>🌐 Fase 2: Infraestructura de Red (VPC)
**Objetivo:** Crear el terreno digital (VPC, Subnets Públicas/Privadas, NAT Gateways).

**Ejecución:**
```bash
cd iac/live/vpc
terragrunt init
terragrunt apply -auto-approve
```

**Validación:**
* Entrar a la Consola AWS -> VPC.
* Verificar que existe `gitops-platform-dev-vpc` y sus subnets asociadas.

---

## <a name="fase-3"></a>☸️ Fase 3: Cómputo (Cluster EKS)
**Objetivo:** Levantar el Cluster Kubernetes y los Nodos de Trabajo (EC2).
**Nota:** Este paso tarda entre 10 a 15 minutos. Ideal para explicar la arquitectura durante la espera.

**Ejecución:**
```bash
cd ../eks
terragrunt init
terragrunt apply -auto-approve
```

**Conexión Crítica:**
Una vez termine, debemos conectar nuestro `kubectl` local al nuevo cluster:
```bash
aws eks update-kubeconfig --name eks-gitops-dev --region us-east-1
```

**Validación:**
```bash
kubectl get nodes
# Debes ver los nodos en estado 'Ready'.
```

---

## <a name="fase-4"></a>🏗️ Fase 4: Plataforma (ArgoCD & Ingress)
**Objetivo:** Instalar el cerebro de operaciones (ArgoCD) y el gestor de tráfico (ALB Controller).

**Paso 4.1: AWS Load Balancer Controller**
Este componente hablará con AWS para crear Balanceadores reales.
```bash
# Volver a la raíz
cd ../../..
./scripts/setup_alb_controller.sh
```

**Paso 4.2: ArgoCD (El Operador GitOps)**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f [https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml](https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml)
```

**Acceso a ArgoCD (Opcional para mostrar):**
1.  Obtener password: `./scripts/get_argocd_pass.sh`
2.  Exponer puerto: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
3.  Entrar en `https://localhost:8080` (Usuario: `admin`).

---

## <a name="fase-5"></a>🚀 Fase 5: Despliegue de Aplicación (n8n)
**Objetivo:** Usar GitOps para desplegar n8n Enterprise.
**¿Qué pasa aquí?** Le decimos a Kubernetes: "Quiero lo que está definido en este archivo". ArgoCD o K8s se encargarán de crear el Ingress, el Servicio y los Pods.

**Ejecución:**
```bash
kubectl apply -f gitops/apps/n8n-app.yaml
```

**Espera de Provisión:**
AWS tardará unos 2-3 minutos en crear el Balanceador de Carga (ALB) y asignarle una DNS.
Monitorea el estado con:
```bash
kubectl get ingress -n n8n-system --watch
# Espera hasta que aparezca una dirección larga en 'ADDRESS' (ej: k8s-n8nsystem-...).
```

---

## <a name="fase-6"></a>🍒 Fase 6: LA PRUEBA DE FUEGO (Configuración n8n)
**Objetivo:** Demostrar que la arquitectura funciona end-to-end. Configuraremos un robot simple que responde "Hola Mundo".

**1. Acceder a n8n:**
* Copia la URL del `ADDRESS` obtenida en el paso anterior.
* Pégala en el navegador.
* Crea la cuenta de administrador inicial (email/password).

**2. Crear el Workflow "Hola Jose":**
* Haz clic en **"Add first step"**.
* Busca **"Webhook"**. Selecciónalo.
* **Configuración del Webhook:**
    * **HTTP Method:** `GET`
    * **Path:** `estado`
    * **Respond:** Cambiar de "Immediately" a **"Using 'Respond to Webhook' Node"** (¡Crucial!).
* Cierra el nodo Webhook.

**3. Crear la Respuesta:**
* Haz clic en el `+` al lado del Webhook.
* Busca **"Respond to Webhook"**.
* **Configuración:**
    * **Respond With:** `JSON`
    * **Response Body:**
        ```json
        { "mensaje": "¡Hola Jose! Tu Cluster Enterprise está VIVO 🤖🚀" }
        ```
* Cierra el nodo.

**4. Ejecución y Prueba:**
* Haz clic en el botón **"Execute Workflow"** (abajo al centro). Se pondrá en "Waiting...".
* En una nueva pestaña del navegador, pega tu URL pública y agrega: `/webhook-test/estado`.
    * *Ejemplo:* `http://k8s-n8n...amazonaws.com/webhook-test/estado`
* **¡ÉXITO!** Deberías ver el JSON de respuesta en el navegador.

---

## <a name="fase-7"></a>💀 Fase 7: Protocolo de Destrucción Forense
**Objetivo:** Eliminar absolutamente todo para evitar costos.
**Advertencia:** Este es el proceso de "Tierra Quemada". No hay retorno.

**Paso 7.1: El Destructor Omnipotente (V9)**
Este script intenta borrar todo en orden lógico: Apps -> IAM -> Cómputo -> Redes -> Residuos.
```bash
./scripts/forensic_nuke_v9_omnipotent.sh
# Tiempo estimado: 15-20 minutos. Ve por un café ☕.
```

**Paso 7.2: El Francotirador de VPC (V10) - Solo si es necesario**
Si la V9 termina pero dice que la VPC sigue viva (por tiempos de espera de AWS):
```bash
./scripts/forensic_nuke_v10_vpc_terminator.sh
# Ejecutará un bucle hasta confirmar la muerte de la VPC.
```

**Paso 7.3: La Auditoría Final (La Verdad)**
Verifica que no quede NADA cobrando.
```bash
./scripts/audit_finops_ultimate.sh
# Objetivo: Ver todo en VERDE ([PASS]) y contadores en 0.
```

**Paso 7.4: Borrado del Backend (El Adiós)**
Elimina el historial de Terraform (S3 y DynamoDB).
```bash
./scripts/nuke_backend_smart.sh
```

---
**🏁 Fin del Laboratorio.**
