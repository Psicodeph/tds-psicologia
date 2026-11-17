-- ============================================================================
--  13 - Unir a Adrian y dejar una sola evaluación
--
--  Los dos registros son la misma evaluación del 23-feb-2025 cargada dos
--  veces con el nombre escrito distinto. Ansiedad, Loehr y temperamento son
--  idénticos; el único dato que difiere es el CI (87 contra 90).
--
--  Según lo decidido: se conserva el nombre "Adrian Leonel Osorio Lezama" y
--  el CI 90 (diagnóstico Normal).
--
--  Se puede ejecutar más de una vez. La tabla `perfiles` no se toca.
-- ============================================================================

-- 1. Unir los dos atletas en el del nombre bien escrito
select public.unificar_atletas(
  'c191dd2a-03ab-4f6e-b5e8-7b50badaa58e',   -- se conserva: Adrian Leonel Osorio Lezama
  'fbcb0ea6-c3fc-4061-a9ca-47b8ee365ce0'    -- se borra:    ADRIAN LIONEL OSORIO LEZMA
) as "unión";

-- 2. Quitar las evaluaciones que quedaron repetidas el mismo día con los
--    mismos puntajes (ansiedad, Loehr y temperamento). Conserva la primera.
with ordenadas as (
  select id,
         row_number() over (
           partition by atleta_id, tipo, fecha, datos
           order by created_at, id
         ) as nro
    from public.evaluaciones
),
borradas as (
  delete from public.evaluaciones
   where id in (select id from ordenadas where nro > 1)
  returning tipo
)
select coalesce(tipo, 'TOTAL') as "duplicado exacto quitado", count(*) as cuantos
  from borradas group by rollup(tipo);

-- 3. El CI correcto es 90: se quita el 87 de ese día
with a_borrar as (
  select e.id
    from public.evaluaciones e
    join public.atletas a on a.id = e.atleta_id
   where a.nombre ilike '%OSORIO%'
     and e.tipo  = 'ci'
     and e.fecha = date '2025-02-23'
     and e.datos->>'ci' = '87'
),
borradas as (
  delete from public.evaluaciones where id in (select id from a_borrar) returning id
)
select (select count(*) from borradas) as "CI 87 quitados";

-- 4. Verificación
select a.nombre,
       count(*)                                           as evaluaciones,
       string_agg(distinct e.tipo, ', ' order by e.tipo)   as pruebas,
       max(e.datos->>'ci')                                 as "CI que quedó"
  from public.atletas a
  join public.evaluaciones e on e.atleta_id = a.id
 where a.nombre ilike '%OSORIO%'
 group by a.nombre;
