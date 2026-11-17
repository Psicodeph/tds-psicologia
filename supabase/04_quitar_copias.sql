-- ============================================================================
--  04 - Quitar las copias de CI y temperamento
--
--  Ejecutar DESPUÉS de revisar la lista de la consulta 03.
--
--  Borra únicamente las evaluaciones de CI y temperamento cuyo valor es
--  idéntico al de la medición anterior del mismo atleta, es decir, las que
--  la app vieja copió sola al hacer una reevaluación.
--
--  NO toca:
--    · las que tienen un valor distinto (reaplicaciones reales),
--    · ansiedad ni Loehr (ahí repetir sí es seguimiento real),
--    · la tabla `perfiles`, que sigue intacta como respaldo.
--
--  Se puede ejecutar más de una vez. Si alguna vez volvés a correr el
--  script 01, corré este después otra vez.
-- ============================================================================
with ordenadas as (
  select e.id, e.atleta_id, e.tipo, e.fecha, e.created_at,
         coalesce(e.datos->>'ci', e.datos->>'temperamento', '—') as valor,
         lag(coalesce(e.datos->>'ci', e.datos->>'temperamento', '—')) over (
           partition by e.atleta_id, e.tipo order by e.fecha, e.created_at
         ) as valor_anterior
    from public.evaluaciones e
   where e.tipo in ('ci','temperamento')
),
copias as (
  select id from ordenadas
   where valor_anterior is not null
     and valor = valor_anterior
),
borradas as (
  delete from public.evaluaciones
   where id in (select id from copias)
  returning tipo
)
select tipo as "prueba", count(*) as "copias quitadas"
  from borradas group by tipo
union all
select 'TOTAL', count(*) from borradas;
