# 💰 FinOps Protocol: Estrategia de Costos y Gobernanza

**Proyecto:** AWS EKS Enterprise n8n Platform
**Responsable:** Cloud Architecture Team

Este documento define la estrategia de **Operaciones Financieras (FinOps)** aplicada a este proyecto para garantizar la eficiencia de costos, la visibilidad del gasto y la eliminación de residuos (Waste Management) en entornos efímeros.

---

## 1. Principios de Diseño FinOps

1.  **Efímero por Defecto:** La infraestructura de desarrollo (Dev) está diseñada para ser destruida, no apagada.
2.  **Auditoría Continua:** No se asume que un recurso se borró; se verifica mediante auditoría forense.
3.  **Costo $0 Garantizado:** El estado final de cualquier prueba de concepto debe ser una factura de AWS limpia.

---

## 2. Generadores de Costo (Cost Drivers)

Identificamos los recursos de alto impacto financiero en esta arquitectura:

| Recurso | Modelo de Costo | Impacto | Estrategia de Mitigación |
| :--- | :--- | :--- | :--- |
| **NAT Gateway** | Por hora + GB procesado | 🔴 Alto | Eliminar inmediatamente tras destruir el cluster. |
| **EKS Control Plane** | Por hora (~$0.10/h) | 🔴 Alto | No dejar clusters "durmiendo" el fin de semana. |
| **ALB (Load Balancer)** | Por hora + LCU | 🟠 Medio | El Ingress Controller gestiona su ciclo de vida. |
| **EBS (Discos)** | Por GB provisionado | 🟠 Medio | Uso de PVCs dinámicos que se borran con el cluster. |
| **Elastic IPs** | Por hora (si no se usa) | 🟡 Bajo | Liberación automática mediante scripts forenses. |

---

## 3. Protocolo de Destrucción Forense ("The Nuke Strategy")

A diferencia de un `terraform destroy` estándar, este proyecto utiliza un enfoque de **"Tierra Quemada" (Scorched Earth)** para manejar dependencias circulares y recursos huérfanos.

### El Ciclo de Limpieza:
1.  **Capa Lógica (K8s):** Eliminación interna de Ingress y PVCs para disparar la limpieza de la nube por parte de los controladores.
2.  **Capa de Identidad (IAM):** Eliminación de Roles y Políticas creadas manualmente fuera de Terraform.
3.  **Capa de Cómputo (Fuerza Bruta):** Eliminación directa de Node Groups y Cluster vía AWS CLI para evitar bloqueos de estado de Terraform.
4.  **Capa de Red (Deep Clean):**
    * Detección y desconexión forzada de Interfaces de Red (ENIs).
    * Revocación masiva de reglas de Security Groups (romper dependencias circulares).
    * Eliminación atómica de la VPC.
5.  **Auditoría Final:** Escaneo de la región para certificar 0 recursos activos.

---

## 4. Auditoría y Verificación

Para garantizar el cumplimiento de este protocolo, se utiliza la herramienta `audit_finops_ultimate.sh`.

**Criterios de Aprobación de Auditoría:**
* `VPCs Custom`: 0
* `Instancias EC2`: 0
* `Volúmenes EBS`: 0
* `NAT Gateways`: 0
* `Elastic IPs`: 0
* `Load Balancers`: 0

> **Nota:** Cualquier desviación de estos valores tras la ejecución del protocolo de destrucción se considera un incidente FinOps y debe ser remediado manualmente.
