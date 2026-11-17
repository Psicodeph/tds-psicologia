-- ============================================================================
--  14 - Plantel de cada competencia
--
--  Para los estados de prearranque hace falta guardar qué atletas forman el
--  plantel de una competencia, para no tener que elegirlos de nuevo en cada
--  medición.
--
--  Se puede ejecutar más de una vez.
-- ============================================================================

alter table public.competencias
  add column if not exists plantel uuid[] not null default '{}';

-- Una competencia puede repetirse en el tiempo; lo que no puede repetirse es
-- el mismo nombre de aplicación dentro de la misma competencia.
create unique index if not exists aplicaciones_nombre_unico
  on public.aplicaciones (competencia_id, lower(btrim(nombre)));

-- Un atleta tiene una sola medición de prearranque por aplicación. Sin esto,
-- un doble clic al cargar dejaría dos registros del mismo jugador.
create unique index if not exists prearranque_unico
  on public.evaluaciones (atleta_id, aplicacion_id)
  where tipo = 'prearranque' and aplicacion_id is not null;

-- Verificación
select 'competencias.plantel' as columna,
       (select count(*) from information_schema.columns
         where table_schema='public' and table_name='competencias' and column_name='plantel') as existe
union all
select 'índice prearranque_unico',
       (select count(*) from pg_indexes
         where schemaname='public' and indexname='prearranque_unico');
