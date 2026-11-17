-- ============================================================================
--  07 - Decisiones sobre las mediciones distintas del mismo día
--
--  Ejecutar DESPUÉS de la consulta 06.
--
--  Resuelve los tres casos que requerían criterio clínico, según lo decidido:
--    · Darwin Cruz — CI del 23-feb-2025: se conserva 100, se quita el 87
--      (el 87 venía arrastrado del atleta cargado antes en el formulario).
--    · Darwin Cruz — Loehr del 23-feb-2025: se conserva CAT 22 / CVI 23 / NM 25,
--      se quita la versión 20/20/20, que quedó a medio cargar.
--    · Daniel Herrera — Loehr del 5-abr-2025: se conserva EN 23, se quita EN 21.
--
--  Cada borrado está acotado por atleta, prueba, fecha y puntaje exacto, así
--  que no puede afectar a ningún otro registro. No toca la tabla `perfiles`.
--  Se puede ejecutar más de una vez.
-- ============================================================================

with a_borrar as (
  select e.id, a.nombre, e.tipo
    from public.evaluaciones e
    join public.atletas a on a.id = e.atleta_id
   where
     -- Darwin: CI 87 (se conserva el 100)
     (  a.nombre ilike '%DARWIN%CRUZ%'
        and e.tipo = 'ci'
        and e.fecha = date '2025-02-23'
        and e.datos->>'ci' = '87' )
     or
     -- Darwin: Loehr incompleto 20/20/20 (se conserva 22/23/25)
     (  a.nombre ilike '%DARWIN%CRUZ%'
        and e.tipo = 'loehr'
        and e.fecha = date '2025-02-23'
        and e.datos#>>'{escalas,CAT}' = '20'
        and e.datos#>>'{escalas,CVI}' = '20'
        and e.datos#>>'{escalas,NM}'  = '20' )
     or
     -- Daniel: Loehr con EN 21 (se conserva EN 23)
     (  a.nombre ilike '%DANIEL%HERRERA%'
        and e.tipo = 'loehr'
        and e.fecha = date '2025-04-05'
        and e.datos#>>'{escalas,EN}' = '21' )
),
borradas as (
  delete from public.evaluaciones
   where id in (select id from a_borrar)
  returning id
)
select (select count(*) from borradas) as "registros quitados";

-- Verificación final: la primera columna debe decir "sin repeticiones",
-- y abajo se listan los CI que quedaron marcados como prueba inválida.
select coalesce(
         (select string_agg(a.nombre || ' · ' || e.tipo || ' · ' || e.fecha, ' / ')
            from (select atleta_id, tipo, fecha
                    from public.evaluaciones
                   group by atleta_id, tipo, fecha having count(*) > 1) d
            join public.evaluaciones e
              on e.atleta_id = d.atleta_id and e.tipo = d.tipo and e.fecha = d.fecha
            join public.atletas a on a.id = d.atleta_id),
         'sin repeticiones'
       ) as "pruebas repetidas el mismo día";

select a.nombre, e.fecha, e.motivo_invalidez as "CI marcado como prueba inválida"
  from public.evaluaciones e
  join public.atletas a on a.id = e.atleta_id
 where e.tipo = 'ci' and e.invalida
 order by a.nombre;
