-- ============================================================================
--  05 - Evaluaciones repetidas el mismo día
--
--  Si un perfil se guardó dos veces el mismo día, el Loehr y la ansiedad
--  quedaron duplicados y aparecerían como historial sin serlo.
--
--  Esta consulta SOLO MUESTRA, no borra nada. Separa:
--    · IDÉNTICA → mismos puntajes: es el mismo perfil guardado dos veces.
--    · DISTINTA → puntajes diferentes el mismo día: revisar a mano.
-- ============================================================================
with mismo_dia as (
  select e.id, e.atleta_id, a.nombre, e.tipo, e.fecha, e.datos, e.created_at,
         count(*)      over (partition by e.atleta_id, e.tipo, e.fecha) as cuantas,
         min(e.datos::text) over (partition by e.atleta_id, e.tipo, e.fecha) as datos_min,
         max(e.datos::text) over (partition by e.atleta_id, e.tipo, e.fecha) as datos_max,
         row_number()  over (partition by e.atleta_id, e.tipo, e.fecha
                             order by e.created_at, e.id)                as nro
    from public.evaluaciones e
    join public.atletas a on a.id = e.atleta_id
)
select nombre,
       tipo,
       fecha,
       case tipo
         when 'loehr'    then 'AC '  || coalesce(datos#>>'{escalas,AC}','?') ||
                              ' EN '  || coalesce(datos#>>'{escalas,EN}','?') ||
                              ' CAT ' || coalesce(datos#>>'{escalas,CAT}','?') ||
                              ' CVI ' || coalesce(datos#>>'{escalas,CVI}','?') ||
                              ' NM '  || coalesce(datos#>>'{escalas,NM}','?') ||
                              ' EP '  || coalesce(datos#>>'{escalas,EP}','?') ||
                              ' ACT ' || coalesce(datos#>>'{escalas,ACT}','?')
         when 'ansiedad' then 'estado ' || coalesce(datos->>'estado','—') ||
                              ' / rasgo ' || coalesce(datos->>'rasgo','—')
         else datos::text
       end as puntajes,
       case
         when datos_min = datos_max then
              case when nro = 1 then 'IDÉNTICA · conservar'
                   else               'IDÉNTICA · se puede quitar' end
         else 'DISTINTA · revisar a mano'
       end as situacion
  from mismo_dia
 where cuantas > 1
 order by nombre, tipo, fecha, nro;
