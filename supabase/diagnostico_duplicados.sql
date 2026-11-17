-- ============================================================================
--  Diagnóstico: qué pruebas siguen repetidas el mismo día
--
--  Solo muestra, no cambia nada. Para cada repetición indica:
--    · puntajes_distintos = 1 → son idénticas (sobra una; la quita la 06)
--    · puntajes_distintos = 2 → son distintas (requieren decisión; las 07)
--  Si no devuelve filas, no queda ninguna prueba repetida el mismo día.
-- ============================================================================
select a.nombre, e.tipo, e.fecha,
       count(*)                       as cuantas,
       count(distinct e.datos)        as puntajes_distintos,
       string_agg(distinct e.datos::text, '   ||   ') as datos
  from public.evaluaciones e
  join public.atletas a on a.id = e.atleta_id
 group by a.nombre, e.tipo, e.fecha
having count(*) > 1
 order by a.nombre, e.tipo;
