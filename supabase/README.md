# Consultas de Supabase

Se ejecutan en Supabase → SQL Editor. Conviene guardarlas con el mismo nombre
del archivo, para encontrarlas después.

| Archivo | Para qué | Cuándo |
|---|---|---|
| `00_seguridad_rls.sql` | Deja la base accesible solo con sesión iniciada | Ya ejecutada |
| `01_estructura_atletas.sql` | Crea atletas/sesiones/evaluaciones y migra los perfiles | Ya ejecutada |
| `02_revision_migracion.sql` | Revisa cómo quedó la migración | Después de la 01 |
| `03_ci_temperamento_repetidos.sql` | Muestra qué CI y temperamentos quedaron repetidos. No borra nada | Después de la 02 |
| `04_quitar_copias.sql` | Borra solo las copias que la app vieja generó sola | Después de revisar la 03 |
| `05_repetidas_mismo_dia.sql` | Muestra Loehr y ansiedad duplicados el mismo día. No borra nada | Después de la 04 |
| `06_limpieza_final.sql` | Quita los duplicados exactos y marca los CI con valor 0 como prueba inválida | Después de revisar la 05 |

Todas se pueden ejecutar más de una vez sin duplicar ni perder datos.
La tabla `perfiles` no se toca nunca: queda como respaldo de lo original.
