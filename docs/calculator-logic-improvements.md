# Calculadora — seguimiento lógico y rendimiento

**Estado:** implementación aplicada (2026‑05‑10) conforme alcance actual: sólo cotización pareja desde la fila de la API / par de navegación, avisos ante fallos, caché inicial y sin cambios de layout.

---

## Hallazgos (causa probable de errores al invertir)

1. **Conversión vía pivote implícito VES**  
   `_result` usa `(_amount * fromRate) / toRate` donde `*_rateToVes` interpreta cada `ExchangeRate.value` como “VES por 1 unidad de `code`”. Eso sólo es correcto cuando la API graba ese significado para **todas** las monedas. En COP, el modelo usa `conversionCode` (p. ej. USD) y el número suele significar **1 USD = X COP**, no bolívares por peso (`http_exchange_rate_repository.dart` preserva `value` tal cual llega).

2. **Reglas estáticas de moneda**  
   - Inicialización con `fixedRateCode` fuerza siempre `_toCode = VES`.
   - `_enforceAllowedPair` obliga COP → USD si `_fromCode == COP`, impidiendo pares válidos tras intercambio.
   - `_syncSelectedCurrencies` ante desconocidos fuerza pivotes a `'USD'` y `'VES'`.
   - `_selectedRate` en el caso `"desde"` no‑VES pero no‑VES+VES mezcla criterios y cae en `USD` como respaldo sin relación garantizada con el par activo.

3. **Anti‑patrón de rendimiento / estado**  
   `_syncSelectedCurrencies(ratesSnapshot)` se invoca dentro del `FutureBuilder.builder` durante `build`; modifica `_fromCode`/`_toCode` sin `setState`, lo que puede provocar comportamientos raros y trabajo repetido en cada reconstrucción.

4. **Doble trabajo de red vs inicio**  
   `HomeScreen` usa caché con `FutureBuilder(initialData: _initialSnapshot)` tras `loadSavedSnapshot()`. `CalculatorScreen` arranca sólo `getRates()` sin dato inicial, así que suele esperar más al entrar aun cuando el snapshot ya existe en memoria/`SharedPreferences`.

---

## Contrato API sugerido para lógica 100 % dinámica (confirmar)

Para cada fila `ExchangeRate`:

- Si `conversionCode != null`: **1 `{conversionCode}` = `(displayValue ?? value)` unidades en `displayCurrencyCode`** (caso típico COP cotizado frente a USD).
- Si `conversionCode == null`: **1 `{code}` = `(displayValue ?? value)` unidades en `displayCurrencyCode`** (caso típico USD/EUR frente a VES).

Las conversiones `from → to` deberían resolverse con **esa fila única cuando el par coincide o es el inverso**; sólo usaría puente indirecto cuando no exista fila aplicable pero ambos lados sí tengan cotización contra el mismo pivote conocido desde la API (p. ej. ambos contra VES con la misma semántica).

---

## Rutas actuales y datos que llegan a `CalculatorScreen`

| Entrada | `CalculatorRouteArgs` | Comportamiento actual |
|--------|------------------------|-------------------------|
| Tocar una tarifa | sólo `fixedRateCode: rate.code` | `initialFrom = code`; `initialTo = VES` si no hay otros args — incorrecto para COP (debería abrir contra `conversionCode` u otro eje definido por la fila).
| Chips “conversion rapida” | `fromCode` / `toCode` (VES↔codigo salvo COP↔USD) | Coherente con UI pero `_enforceAllowedPair` rompe inversión en COP.

---

## Mejoras planificadas (post‑aprobación)

**Lógica (sin cambios de UI)**

- Nueva función única tipo `resolveConversion(amount, from, to, snapshot)` que:
  - busque primero cotización explícita de par en la fila adecuada (`code`, `conversionCode`, `displayCurrencyCode`);
  - si el par coincide invertido, use el recíproco;
  - recurra al pivote sólo donde la semántica del modelo lo permita.
- Eliminar o reemplazar reglas especiales COP/USD/VES/`fixedRateCode` por derivación desde la fila `ExchangeRate` del par.
- `_selectedRate` y `_rateLabel` alineados con la misma fuente que alimenta el cálculo.
- `_syncSelectedCurrencies` movido fuera del `build` (p. ej. `initState`/post‑frame/después del future con `mounted`/`setState`).

**Datos de navegación (propuesta)**

- Opción A — Mínimo: desde `RateCard`, pasar además **`fromCode` y `toCode`** inferidos de la misma interpretación anterior (p. ej. COP: `USD`/`COP` según orden mostrado en la tarjeta).
- Opción B — Más robusto: pasar **`rateCode`** (clave de la fila) como “tasas aplicada” cuando el usuario abre desde una tarjeta; la pantalla usa esa fila para semántica aun si el usuario cambia después el par en pickers coherentes.

**Rendimiento**

- Paridad con Home: cargar **`loadSavedSnapshot()`** antes o como `initialData` y, si conviene, no bloquear con historial completo en la primera pintura si el repositorio lo permite sin romper modelo actual.

---

## Preguntas abiertas (respuesta necesaria antes de implementar)

1. ¿Para **todas** las filas de la API vale la lectura anterior de “1 lado base = número en `displayCurrencyCode`” cuando `conversionCode` es no nulo versus nulo?
2. ¿Existe cotización donde **los dos lados** no sean `{code/conversionCode}` y `displayCurrencyCode` (triple o cruz especial)? Si sí, describir uno de ejemplo desde JSON real.
3. Para abrir desde **tarifa COP**, ¿prioridad inicial: **USD → COP** (alineado a “1 USD = … COP”) como en la tarjeta, o **COP → USD** igual que el chip rápido?
4. ¿Se permite añadir campos opcionales a **`CalculatorRouteArgs`** y tocar sólo navegación en `home_screen.dart`/`app_routes.dart`/`calculator_screen.dart` según Opción B?

---

## Registro de implementación

| Fecha | Cambio |
|-------|--------|
| 2026-05-10 | Documento creado: diagnóstico y plan. Código fuente intacto pendiente confirmación. |
| 2026-05-10 | **Implementado:** util `exchange_pair_quote.dart`; `CalculatorScreen` usa cotización **1 anchor = N counter** desde `conversionCode` + `displayCurrencyCode` o, si no hay `conversionCode`, **1 `code` = N `displayCurrency`**. Eliminados pivote universal VES / reglas fijas COP. Intercambio sólo entre las dos monedas del par; pickers externos sin efecto (`noop`). |
| 2026-05-10 | **Navegación:** al tocar una tarifa se envían `fixedRateCode` y, si existe, `fromCode`/`toCode` parseados igual que la fila. |
| 2026-05-10 | **Rendimiento / UX errores:** `FutureBuilder` con `initialData` desde `loadSavedSnapshot()`; spinner mientras llega la fila de una tarifa fija; mensajes cuando no hay datos o falla la red. Monto inicial del controlador **`1`** (sin cambio). |
| 2026-05-10 | **Etiqueta de par bidireccional:** el texto bajo resultado muestra cotización **1 anchor = N counter** y la **reciproca** (1 counter = 1/N anchor) con **`CurrencyFormatter.moneyRate`** (decimales extra si el número es muy pequeño), alineado con `ParsedQuote.convert`; resultado y pegado desde portapapeles usan las mismas reglas para no ver el dólar como `0,00` cuando el monto cotizado es muy pequeño. |
