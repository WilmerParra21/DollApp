# Auditoría en Supabase

Esta app ahora usa la API generada por Supabase para insertar directamente en la tabla `audi_dollap`.

> Si prefieres un enfoque alternativo, también se puede implementar una Edge Function, pero NO es necesario para el flujo de auditoría actual.

## Insertar directamente en la tabla

1. En tu proyecto de Supabase, ve a "Edge Functions"
2. Crea una nueva función llamada `log-audit`
3. Usa este código:

```typescript
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface AuditLog {
  accion: string
  mensaje?: string
  codigo?: string
  metadatos?: Record<string, any>
}

Deno.serve(async (req) => {
  try {
    // Solo permitir POST
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 })
    }

    // Verificar autenticación básica
    const authHeader = req.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response('Unauthorized', { status: 401 })
    }

    const token = authHeader.substring(7)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Crear cliente con service role key (ignora RLS)
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false }
    })

    // Parsear el body
    const auditLog: AuditLog = await req.json()

    // Validar datos requeridos
    if (!auditLog.accion) {
      return new Response('Missing required field: accion', { status: 400 })
    }

    // Insertar en la tabla
    const { error } = await supabase
      .from('audi_dollap')
      .insert({
        accion: auditLog.accion,
        mensaje: auditLog.mensaje,
        codigo: auditLog.codigo,
        metadatos: auditLog.metadatos,
      })

    if (error) {
      console.error('Database error:', error)
      return new Response(`Database error: ${error.message}`, { status: 500 })
    }

    return new Response('OK', { status: 200 })
  } catch (error) {
    console.error('Function error:', error)
    return new Response(`Internal server error: ${error.message}`, { status: 500 })
  }
})
```

## Configurar permisos

Asegúrate de que la función tenga acceso a las variables de entorno:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

La ruta que usa la app es:
`https://<project-ref>.supabase.co/functions/v1/log-audit`

Verifica que la función se llame exactamente `log-audit` y que esté desplegada en el mismo proyecto.

## Políticas RLS

Si prefieres mantener el acceso directo, puedes crear una política RLS que permita INSERT para usuarios anónimos:

```sql
-- Permitir INSERT para usuarios anónimos
CREATE POLICY "Allow anonymous inserts" ON audi_dollap
FOR INSERT
TO anon
WITH CHECK (true);
```

Sin embargo, usar la Edge Function es más seguro.