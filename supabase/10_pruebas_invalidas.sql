-- ============================================================================
--  10 - Pruebas inválidas en todas las evaluaciones
--
--  Cualquier prueba (CI, temperamento, ansiedad, Loehr) puede quedar marcada
--  como inválida. Hasta ahora solo el CI lo registraba, y el temperamento
--  guardaba el valor interno "__invalida__", que terminaba mostrándose tal
--  cual en pantalla.
--
--  Esta consulta:
--    1. Agrega a `perfiles` la columna donde el formulario anota qué pruebas
--       quedaron inválidas.
--    2. Rellena esa columna con lo que ya se podía deducir de los datos.
--    3. Corrige las evaluaciones ya migradas: marca las inválidas y limpia el
--       valor interno para que nunca llegue a la pantalla.
--
--  Se puede ejecutar más de una vez.
-- ============================================================================

-- 1. Dónde anota el formulario las pruebas inválidas
alter table public.perfiles
  add column if not exists invalidas text[];

-- 2. Deducir las que ya existen
update public.perfiles
   set invalidas = (
     select array_agg(x) from (
       select 'ci' as x where ci_diagnostico = 'PRUEBA INVÁLIDA'
       union all
       select 'temperamento' where temperamento in ('__invalida__', 'PRUEBA INVÁLIDA')
     ) t
   )
 where invalidas is null
   and (ci_diagnostico = 'PRUEBA INVÁLIDA'
        or temperamento in ('__invalida__', 'PRUEBA INVÁLIDA'));

-- 3. Corregir las evaluaciones de temperamento ya migradas
update public.evaluaciones
   set invalida         = true,
       motivo_invalidez = coalesce(motivo_invalidez, 'Marcada como inválida en el registro original'),
       datos            = datos - 'temperamento'
 where tipo = 'temperamento'
   and datos->>'temperamento' in ('__invalida__', 'PRUEBA INVÁLIDA');

-- 4. Verificación: ninguna evaluación debe seguir mostrando el valor interno
select tipo,
       count(*) filter (where invalida)                                as "marcadas inválidas",
       count(*) filter (where datos::text like '%\_\_invalida\_\_%')   as "con valor interno (debe ser 0)"
  from public.evaluaciones
 group by tipo
 order by tipo;
