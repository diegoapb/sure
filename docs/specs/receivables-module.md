# Especificación — Módulo de Cuentas de Cobro (Receivables)

**Estado:** aprobada para desarrollo · **Fecha:** 2026-08-18 · **Rama base:** `dokploy`

## 1. Resumen

Módulo para gestionar dinero que **le deben al usuario**: préstamos personales otorgados, ventas a crédito, arriendos por cobrar, cuentas de cobro de servicios profesionales. Es el espejo del tipo `Loan` existente (pasivo), pero clasificado como **activo**, con seguimiento de cuotas esperadas, pagos recibidos, intereses y vencimientos.

## 2. Objetivos / No-objetivos

**Objetivos**
- Registrar préstamos/cuentas de cobro con deudor, monto, tasa, plazo y frecuencia de pago.
- Ver el saldo pendiente por deudor y el total agregado en el balance sheet (como activo).
- Generar la tabla de amortización (cuotas esperadas: capital + interés).
- Registrar pagos recibidos y hacer match contra cuotas esperadas (manual o asistido).
- Ver estado por cuota: pendiente, pagada, parcial, vencida.
- Recordatorios/visibilidad de cuotas próximas y vencidas.

**No-objetivos (fase 1)**
- Sincronización con proveedores (Plaid/SimpleFIN) — todo es manual.
- Facturación formal (PDF de cuenta de cobro, numeración DIAN, etc.).
- Interés de mora automático o refinanciaciones.
- Notificaciones al deudor (correo/WhatsApp).

## 3. Arquitectura: cómo encaja en Sure

Sure ya tiene todo el andamiaje:

| Pieza existente | Cómo se reutiliza |
|---|---|
| `Account` + delegated type `Accountable` ([accountable.rb:4](../../app/models/concerns/accountable.rb)) | Nuevo tipo `Receivable` con `classification = "asset"`. El balance, series históricas, multi-moneda y balance sheet salen gratis. |
| `Loan` ([loan.rb](../../app/models/loan.rb)) | Se replica `monthly_payment` y `original_balance` (misma matemática, signo contrario). |
| `Entry`/`Transaction`/`Valuation` | Cada pago recibido es una `Transaction` normal en la cuenta receivable (reduce el saldo) o una transferencia hacia una cuenta depository. |
| `RecurringTransaction` (tu módulo en `dokploy`) | Las cuotas esperadas se modelan como patrón recurrente vinculado; el match manual de pagos ya existe ahí. |
| Vistas por tipo (`app/views/loans`, rutas `resources :loans`) | Mismo patrón: `app/views/receivables`, `resources :receivables`. |

**Decisión clave:** las cuotas esperadas viven en una tabla propia (`receivable_installments`) generada desde la amortización, y el módulo de recurrentes se usa opcionalmente para el flujo de matching. Esto evita forzar el modelo de recurrentes (pensado para gastos/ingresos por día-del-mes) a soportar amortización con interés.

## 4. Modelo de datos

### 4.1 `receivables` (accountable)
| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `debtor_name` | string | requerido (persona/empresa que debe) |
| `debtor_contact` | string, null | teléfono/email informativo |
| `interest_rate` | decimal, null | % anual; null = sin interés |
| `rate_type` | string, null | `fixed` (única soportada en fase 1) |
| `term_months` | integer, null | null = sin plazo definido (cobro abierto) |
| `payment_frequency` | string | `monthly` (default), `biweekly`, `weekly`, `custom` |
| `start_date` | date | fecha de desembolso/origen |
| `subtype` | string | `personal_loan`, `sale_credit`, `rent`, `services`, `other` |
| `notes` | text, null | |

El monto original se deriva de la primera valuación de la cuenta (igual que `Loan#original_balance`). El saldo pendiente es el balance normal de la cuenta.

### 4.2 `receivable_installments`
| Campo | Tipo | Notas |
|---|---|---|
| `receivable_id` | fk | |
| `number` | integer | 1..n |
| `due_date` | date | |
| `principal_amount` / `interest_amount` / `total_amount` | decimal | de la amortización |
| `paid_amount` | decimal, default 0 | acumulado de pagos aplicados |
| `status` | string | `pending`, `partial`, `paid`, `overdue` (derivado, cacheado) |
| `paid_at` | date, null | fecha del último pago aplicado |

### 4.3 `receivable_payments` (join pago ↔ cuota)
| Campo | Tipo | Notas |
|---|---|---|
| `receivable_installment_id` | fk | |
| `transaction_id` | fk | la transacción real registrada |
| `amount_applied` | decimal | permite pagos parciales y un pago que cubre varias cuotas |

## 5. Reglas de negocio

1. **Amortización (fase 1: cuota fija, sistema francés).** Igual fórmula que `Loan#monthly_payment`. Sin interés → capital / n cuotas. Sin plazo (`term_months` null) → no se generan cuotas; solo saldo abierto.
2. **Regeneración del plan.** Editar tasa/plazo/frecuencia regenera solo las cuotas **futuras no pagadas**; las pagadas/parciales quedan intactas.
3. **Aplicación de pagos.** Un pago se aplica primero a la cuota vencida más antigua (interés antes que capital dentro de la cuota). El usuario puede reasignar manualmente.
4. **Estados.** `overdue` = `due_date` pasada y `paid_amount < total_amount`. Se recalcula al aplicar pagos y en un job diario (sidekiq-cron, patrón ya usado).
5. **Registro contable.** El desembolso inicial se registra como valuación de apertura (o transferencia desde una cuenta depository si el usuario lo indica). Cada pago recibido: transferencia receivable → depository (reduce el activo receivable, aumenta efectivo), o transacción simple en la receivable si el destino no está en Sure.
6. **Multi-moneda.** Igual que cualquier cuenta: la receivable tiene su moneda; conversión vía `Money` existente.
7. **Condonación / castigo.** Acción "dar de baja saldo" → valuación de ajuste a un nuevo valor (reutiliza reconciliación existente), con nota.

## 6. Casos de uso

| # | Caso de uso | Actor | Flujo principal |
|---|---|---|---|
| CU1 | Crear cuenta de cobro | Usuario | Nueva cuenta → tipo "Cuenta por cobrar" → deudor, monto, tasa, plazo, frecuencia, fecha → se genera plan de cuotas y aparece como activo. |
| CU2 | Ver detalle | Usuario | Página de la cuenta: saldo pendiente, progreso (pagado/total), tabla de cuotas con estados, historial de pagos. |
| CU3 | Registrar pago recibido | Usuario | Desde la cuenta: "Registrar pago" → monto, fecha, cuenta destino (opcional) → se crea la transacción y se aplica a cuotas (sugerencia automática, editable). |
| CU4 | Match de transacción existente | Usuario | Una consignación ya importada en su cuenta bancaria se vincula como pago de una cuota (flujo análogo al match manual de recurrentes). |
| CU5 | Ver cuotas próximas/vencidas | Usuario | Vista/widget "Por cobrar": cuotas de todos los deudores ordenadas por vencimiento, con vencidas destacadas. |
| CU6 | Editar condiciones | Usuario | Cambiar tasa/plazo → regenera cuotas futuras (confirmación previa). |
| CU7 | Cerrar / condonar | Usuario | Saldo llega a 0 → cuenta se marca pagada (cerrable). Condonación parcial vía ajuste con nota. |
| CU8 | Cobro abierto sin plan | Usuario | Cuenta sin plazo: solo saldo pendiente y pagos libres, sin cuotas. |

## 7. Escenarios de prueba (aceptación)

1. **Préstamo simple sin interés:** $1.000.000 a 10 meses → 10 cuotas de $100.000; pagar 3 → saldo $700.000, progreso 30%.
2. **Préstamo con interés fijo:** $5.000.000, 24 meses, 18% anual → cuota fija ≈ fórmula francesa; suma de capital de las 24 cuotas = principal (ajuste de redondeo en la última).
3. **Pago parcial:** cuota de $250.000, pago de $150.000 → estado `partial`, siguiente pago de $100.000 la completa.
4. **Pago que cubre varias cuotas:** pago de $500.000 con cuotas de $200.000 → 2 pagas + 1 parcial de $100.000.
5. **Cuota vencida:** job diario marca `overdue` al pasar `due_date`; pagar la vuelve `paid`.
6. **Edición de condiciones:** con 5 cuotas pagadas, cambiar plazo → cuotas 1-5 intactas, 6+ regeneradas.
7. **Transferencia como pago:** pago con destino a cuenta depository crea transferencia (dos entries) y ambos saldos cuadran.
8. **Multi-moneda:** receivable en USD con familia en COP se muestra convertida en balance sheet.
9. **Cobro abierto:** sin `term_months`, no hay cuotas; pagos libres reducen saldo hasta 0.

## 8. UI

- **Creación:** entrada "Cuenta por cobrar" en el selector de tipo de cuenta (icono `hand-coins`, color verde de activos), formulario en `app/views/receivables/` siguiendo el patrón de `loans`.
- **Detalle:** tab de cuotas (tabla: #, vencimiento, capital, interés, total, pagado, estado con badge) + tab de actividad (entries estándar). Componentes ViewComponent para la fila de cuota y el badge de estado.
- **Dashboard "Por cobrar":** sección accesible desde el sidebar; lista agregada de cuotas próximas (30 días) y vencidas, con total por cobrar.
- Todo con i18n (`receivables.*`), tokens del design system, Hotwire (Turbo frames para aplicar pagos sin recargar).

## 9. API (fase 2, opcional)

`/api/v1/receivables` (CRUD) y `/api/v1/receivables/:id/payments` (crear pago). Requiere: controladores, Jbuilder, tests Minitest de comportamiento, specs rswag docs-only y regeneración de `docs/api/openapi.yaml` (checklist issue #944).

## 10. Fases de implementación

| Fase | Alcance | Tamaño estimado |
|---|---|---|
| **F1 — Núcleo** | Accountable `Receivable`, migraciones (3 tablas), amortización, CRUD + vistas de detalle con cuotas, registro de pagos con aplicación automática, i18n, tests de modelo | La más grande (~60% del módulo) |
| **F2 — Flujos** | Match de transacciones existentes, pagos como transferencia, edición/regeneración de plan, job de vencidos, dashboard "Por cobrar" | Mediana |
| **F3 — Extras** | API v1 + OpenAPI, condonación/ajustes, widget en home, datos demo | Pequeña |

## 11. Decisiones tomadas (2026-08-18)

1. **Patrón de integración:** seguir el patrón existente sin modificar lógica central; solo archivos nuevos + los puntos de registro mínimos (lista de tipos, rutas, locales) para minimizar conflictos con upstream.
2. **Frecuencia:** fase 1 solo `monthly`. El campo `payment_frequency` queda en el esquema con default `monthly` para futuras frecuencias.
3. **Tasa de interés:** el usuario ingresa tasa **anual nominal** y se divide /12, igual que `Loan#monthly_payment`. Se documenta en el formulario (hint i18n).
4. **Relación con recurrentes:** las cuotas viven en `receivable_installments` (tabla propia, independiente de `RecurringTransaction`). El flujo de match de pagos reutiliza el patrón de UI del match manual de recurrentes, pero con controlador y lógica propios — ambos módulos se mantienen independientes.
