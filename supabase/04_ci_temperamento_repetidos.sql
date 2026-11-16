-- ============================================================================
--  04 - CI y temperamento repetidos
--
--  La app vieja, al hacer una reevaluación, copiaba el CI y el temperamento
--  al registro nuevo. Por eso algunas pruebas figuran aplicadas dos veces
--  cuando en realidad se aplicaron una sola.
--
--  Esta consulta SOLO MUESTRA, no borra nada. Separa:
--    · COPIA      → mismo valor en otra fecha: no es una aplicación real.
--    · REAPLICADA → valor distinto: sí se volvió a tomar la prueba.
-- ============================================================================
with repetidas as (
  select e.id, e.atleta_id, a.nombre, e.tipo, e.fecha,
         coalesce(e.datos->>'ci', e.datos->>'temperamento', '—') as valor,
         lag(coalesce(e.datos->>'ci', e.datos->>'temperamento', '—')) over (
           partition by e.atleta_id, e.tipo order by e.fecha, e.created_at
         ) as valor_anterior,
         row_number() over (
           partition by e.atleta_id, e.tipo order by e.fecha, e.created_at
         ) as nro
    from public.evaluaciones e
    join public.atletas a on a.id = e.atleta_id
   where e.tipo in ('ci','temperamento')
     and e.atleta_id in (
       select atleta_id from public.evaluaciones
        where tipo in ('ci','temperamento')
        group by atleta_id, tipo having count(*) > 1
     )
)
select nombre,
       tipo,
       fecha,
       valor,
       case
         when nro = 1                 then 'original'
         when valor = valor_anterior  then 'COPIA (se puede quitar)'
         else                              'REAPLICADA (conservar)'
       end as situacion
  from repetidas
 order by nombre, tipo, fecha;
