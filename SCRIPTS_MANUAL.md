# 📜 Manual de Operaciones de Scripts (The DevOps Arsenal)

**Proyecto:** AWS EKS Enterprise n8n
**Ubicación:** `./scripts/`
**Objetivo:** Documentación técnica de herramientas de automatización, auditoría FinOps y destrucción forense.

Este repositorio contiene una colección de scripts Bash diseñados para gestionar el ciclo de vida completo de la infraestructura. A continuación se detalla su uso ordenado por fases.

---

## 🏗️ Fase 1: Inicialización y Setup (Day 0)
Estos scripts se ejecutan **antes** o **durante** el despliegue de Terraform.

### 1. `setup_backend.sh`
* **Función:** Crea los recursos pre-requisitos para Terraform: El Bucket S3 (con cifrado y versionado) y la Tabla DynamoDB (para bloqueo de estado).
* **Cuándo usar:** **PRIMER PASO ABSOLUTO**. Ejecutar antes de cualquier comando `terragrunt init`.
* **Comando:** `./scripts/setup_backend.sh`

### 2. `check_backend.sh`
* **Función:** Verifica si el Bucket S3 y la Tabla DynamoDB existen y son accesibles.
* **Cuándo usar:** Para diagnosticar problemas de Terraform o verificar si la limpieza fue exitosa.
* **Comando:** `./scripts/check_backend.sh`

### 3. `setup_alb_controller.sh`
* **Función:** Instala el *AWS Load Balancer Controller* en el cluster EKS. Crea las políticas IAM, el Rol con OIDC y despliega el Helm Chart.
* **Cuándo usar:** **DESPUÉS** de que el cluster EKS esté activo (Fase 3 del Runbook).
* **Comando:** `./scripts/setup_alb_controller.sh`

---

## 💰 Fase 2: Auditoría FinOps (Day 2 / Mantenimiento)
Estos scripts no modifican nada, solo leen y reportan costos potenciales.

### 4. `audit_finops_ultimate.sh` (🏆 RECOMENDADO)
* **Función:** La herramienta de auditoría más avanzada. Escanea Cómputo, Redes (incluyendo ENIs ocultas), Storage, EKS, IAM y Logs.
* **Cuándo usar:**
    1.  Para ver qué tienes desplegado.
    2.  **CRÍTICO:** Ejecutar después de la destrucción para confirmar costo $0.
* **Comando:** `./scripts/audit_finops_ultimate.sh`

### 5. `audit_finops_extreme.sh` (Legacy)
* **Función:** Versión anterior del auditor. Menos detallada en temas de redes profundas.
* **Estado:** Deprecado en favor de `ultimate`.

---

## ☢️ Fase 3: Protocolo de Destrucción (The Nuke)
Scripts diseñados para eliminar infraestructura. **Úsese con extrema precaución.**

### 6. `forensic_nuke_v9_omnipotent.sh` (🏆 PRINCIPAL)
* **Función:** El script de destrucción definitivo ("All-in-One").
    * Limpia K8s (Ingress/PVCs).
    * Limpia IAM (Roles manuales).
    * Limpia Cómputo (Cluster/Nodos) vía AWS CLI (bypass de errores de Terraform).
    * **VPC Cleaner:** Entra en la VPC y elimina dependencias internas antes de borrarla.
    * Limpia residuos (ECR, RDS, Snapshots, Logs).
* **Cuándo usar:** Es el **PRIMER SCRIPT** a ejecutar cuando quieras destruir el entorno.
* **Comando:** `./scripts/forensic_nuke_v9_omnipotent.sh`

### 7. `forensic_nuke_v10_vpc_terminator.sh` (🏆 FRANCOTIRADOR)
* **Función:** Un script especializado en eliminar UNA sola VPC rebelde. Ejecuta un bucle de intentos hasta que AWS libera los candados (ej. NAT Gateways borrándose).
* **Cuándo usar:** Si la V9 termina pero la VPC sigue viva por tiempos de espera de AWS.
* **Comando:** `./scripts/forensic_nuke_v10_vpc_terminator.sh`

### 8. `nuke_backend_smart.sh` (FINALIZADOR)
* **Función:** Elimina el Bucket S3 y la Tabla DynamoDB (el Backend).
* **Cuándo usar:** **ÚLTIMO PASO**. Solo ejecutar cuando ya no planees usar Terraform nunca más para este proyecto.
* **Comando:** `./scripts/nuke_backend_smart.sh`

---

## 🚑 Fase 4: Herramientas Quirúrgicas (Troubleshooting)
Scripts específicos para resolver bloqueos ("Deadlocks") cuando la destrucción automática falla.

### 9. `forensic_sg_wiper.sh`
* **Función:** Soluciona el problema de **"DependencyViolation"** en Security Groups. Descarga las reglas en JSON, las revoca todas y luego borra los grupos vacíos.
* **Cuándo usar:** Si la V9/V10 falla diciendo que los Security Groups tienen dependencias.

### 10. `forensic_eni_killer.sh`
* **Función:** Busca Interfaces de Red (ENIs) "fantasmas" o gestionadas por AWS que impiden borrar una VPC y las fuerza a desconectarse.
* **Cuándo usar:** Si la VPC no se borra y el auditor dice que hay ENIs activas.

### 11. `surgical_vpc_extraction.sh`
* **Función:** Un script manual paso a paso para desmantelar una VPC componente por componente.
* **Cuándo usar:** Herramienta de diagnóstico si todo lo demás falla.

---

## 📂 Archivos Legacy / Auxiliares
Estos scripts fueron pasos intermedios en el desarrollo o utilidades menores.

* `forensic_nuke_v5_ultimate.sh`: Versión estable previa (sin VPC cleaner atómico).
* `forensic_nuke_v6_fail_safe.sh`: Versión que introdujo el bypass de Terragrunt.
* `forensic_nuke_v8_final_fusion.sh`: La base de la V9.
* `nuke_vpc.sh`: Utilidad simple para borrar una VPC (absorbida por V9).
* `nuke_loadbalancers.sh`: Utilidad para borrar LBs (absorbida por V9).
* `nuke_zombies.sh`: Utilidad para borrar Logs y Alias KMS (absorbida por V9).

---

## ⚡ Flujo de Trabajo Recomendado (Workflow)

### Para Crear:
1.  `./scripts/setup_backend.sh`
2.  (Ejecutar Terragrunt VPC & EKS)
3.  `./scripts/setup_alb_controller.sh`

### Para Destruir (Costo $0):
1.  `./scripts/forensic_nuke_v9_omnipotent.sh` (El destructor principal)
2.  `./scripts/forensic_nuke_v10_vpc_terminator.sh` (Si la VPC resiste)
3.  `./scripts/audit_finops_ultimate.sh` (Verificar todo en verde/0)
4.  `./scripts/nuke_backend_smart.sh` (Borrar el estado)
