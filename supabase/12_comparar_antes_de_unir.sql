-- ============================================================================
--  12 - Qué tiene cada uno antes de unirlos
--
--  Muestra lado a lado el historial de los dos atletas que se van a unificar.
--  Si las fechas coinciden, es la misma evaluación cargada dos veces con el
--  nombre escrito distinto. Si son fechas distintas, son sesiones reales y al
--  unirlos queda el historial completo.
--
--  Reemplazar los dos identificadores por los del par a revisar.
-- ============================================================================
with par as (
  select 'c191dd2a-03ab-4f6e-b5e8-7b50badaa58e'::uuid as id_a,
         'fbcb0ea6-c3fc-4061-a9ca-47b8ee365ce0'::uuid as id_b
)
select e.fecha,
       e.tipo,
       case when e.atleta_id = par.id_a then '← ' || a.nombre else '' end as "atleta A",
       case when e.atleta_id = par.id_b then '→ ' || a.nombre else '' end as "atleta B",
       coalesce(
         e.datos->>'ci',
         e.datos->>'temperamento',
         nullif(concat_ws(' / ', e.datos->>'estado', e.datos->>'rasgo'), ''),
         nullif(concat_ws(' ',
           'AC'  || (e.datos#>>'{escalas,AC}'),
           'EN'  || (e.datos#>>'{escalas,EN}'),
           'CAT' || (e.datos#>>'{escalas,CAT}'),
           'CVI' || (e.datos#>>'{escalas,CVI}'),
           'NM'  || (e.datos#>>'{escalas,NM}'),
           'EP'  || (e.datos#>>'{escalas,EP}'),
           'ACT' || (e.datos#>>'{escalas,ACT}')), ''),
         case when e.invalida then 'Prueba inválida' end,
         '—'
       ) as resultado
  from par
  join public.evaluaciones e on e.atleta_id in (par.id_a, par.id_b)
  join public.atletas a      on a.id = e.atleta_id
 order by e.tipo, e.fecha;
