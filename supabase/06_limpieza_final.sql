-- ============================================================================
--  06 - Limpieza final de los duplicados del mismo día
--
--  Ejecutar DESPUÉS de revisar la consulta 05.
--
--  Hace tres cosas:
--    1. Borra las evaluaciones IDÉNTICAS del mismo día (mismo atleta, misma
--       prueba, misma fecha y mismos puntajes). Conserva siempre la primera.
--    2. Marca como PRUEBA INVÁLIDA los CI cargados con valor 0, que no es un
--       puntaje posible: quedan registrados como aplicados pero sin resultado.
--    3. Deja intactas las evaluaciones con puntajes DISTINTOS el mismo día,
--       que requieren criterio clínico.
--
--  No toca la tabla `perfiles`. Se puede ejecutar más de una vez.
-- ============================================================================

-- 1. Duplicados exactos del mismo día
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
select 'duplicados exactos quitados' as accion,
       coalesce(tipo, 'TOTAL')       as prueba,
       count(*)                      as cuantos
  from borradas
 group by rollup(tipo);

-- 2. CI con valor 0 → prueba inválida
update public.evaluaciones
   set datos            = jsonb_build_object('diagnostico', 'PRUEBA INVÁLIDA'),
       invalida         = true,
       motivo_invalidez = coalesce(motivo_invalidez, 'Sin puntaje válido en el registro original')
 where tipo = 'ci'
   and (datos->>'ci') = '0';

-- 3. Qué quedó por revisar a mano (puntajes distintos el mismo día)
select a.nombre, e.tipo, e.fecha, count(*) as "mediciones distintas ese día"
  from public.evaluaciones e
  join public.atletas a on a.id = e.atleta_id
 group by a.nombre, e.tipo, e.fecha
having count(*) > 1
 order by a.nombre, e.tipo;
