-- ============================================================================
--  TDS / Melany Ordóñez — Estructura nueva: atletas, sesiones y evaluaciones
--  Ejecutar UNA vez en Supabase → SQL Editor.
--
--  Qué hace:
--    1. Crea las tablas nuevas (atletas, sesiones, evaluaciones, competencias,
--       aplicaciones) con la misma protección RLS que ya tiene `perfiles`.
--    2. Migra los perfiles existentes: cada fila de `perfiles` se convierte en
--       un atleta (unificando nombres escritos distinto) + una sesión + una
--       evaluación POR CADA prueba que tenga cargada (CI, temperamento,
--       ansiedad, Loehr).
--
--  Qué NO hace: no toca ni borra la tabla `perfiles`. Queda intacta como
--  respaldo. La app vieja sigue funcionando igual hasta que se confirme todo.
--
--  Se puede ejecutar más de una vez sin duplicar datos.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
--  1. TABLAS
-- ─────────────────────────────────────────────────────────────────────────

-- Un atleta = una persona. Sus datos estables viven acá.
create table if not exists public.atletas (
  id                uuid primary key default gen_random_uuid(),
  nombre            text not null,
  sexo              text,              -- 'Masculino' | 'Femenino' | otro
  fecha_nacimiento  date,
  deporte           text,              -- 'Fútbol', 'Atletismo', ...
  organizacion      text,              -- 'TDS - FFH', club, 'Particular'
  categoria         text,              -- 'Sub-15', 'Mayor', libre según deporte
  posicion          text,
  centro            text,              -- centro de formación / sede
  notas             text,
  activo            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Una sesión = un encuentro de evaluación, el que produce un informe.
-- Agrupa las pruebas aplicadas ese día. Las mediciones sueltas (prearranque)
-- no necesitan sesión.
create table if not exists public.sesiones (
  id                uuid primary key default gen_random_uuid(),
  atleta_id         uuid not null references public.atletas(id) on delete cascade,
  fecha             date not null,
  contexto          text,              -- 'Evaluación inicial', 'Seguimiento'
  aplicada_por      text,
  interpretada_por  text,
  conclusion        text,
  recomendaciones   text,
  origen_perfil_id  uuid,              -- fila de `perfiles` de la que vino
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Competencias y sus aplicaciones (para los estados de prearranque).
create table if not exists public.competencias (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  organizacion  text,
  fecha_inicio  date,
  notas         text,
  created_at    timestamptz not null default now()
);

create table if not exists public.aplicaciones (
  id              uuid primary key default gen_random_uuid(),
  competencia_id  uuid not null references public.competencias(id) on delete cascade,
  nombre          text not null,       -- 'Pre-partido vs Olimpia'
  fecha           date,
  rival           text,
  notas           text,
  created_at      timestamptz not null default now()
);

-- Una evaluación = UNA prueba aplicada a UN atleta en UNA fecha.
-- Que cada prueba sea su propio registro es lo que permite repetir el Loehr
-- o la ansiedad sin volver a cargar el CI, y ver el historial de cada una.
create table if not exists public.evaluaciones (
  id                uuid primary key default gen_random_uuid(),
  atleta_id         uuid not null references public.atletas(id) on delete cascade,
  tipo              text not null,     -- 'ci','temperamento','ansiedad','loehr','prearranque',...
  fecha             date not null,
  sesion_id         uuid references public.sesiones(id) on delete set null,
  aplicacion_id     uuid references public.aplicaciones(id) on delete set null,
  contexto          text,
  aplicada_por      text,
  interpretada_por  text,
  datos             jsonb not null default '{}'::jsonb,  -- puntajes de la prueba
  interpretacion    text,
  recomendaciones   text,
  invalida          boolean not null default false,
  motivo_invalidez  text,
  origen_perfil_id  uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists evaluaciones_atleta_tipo_fecha
  on public.evaluaciones (atleta_id, tipo, fecha desc);
create index if not exists evaluaciones_tipo_fecha
  on public.evaluaciones (tipo, fecha desc);
create index if not exists evaluaciones_aplicacion
  on public.evaluaciones (aplicacion_id);
create index if not exists sesiones_atleta_fecha
  on public.sesiones (atleta_id, fecha desc);

-- Evita migrar dos veces la misma prueba del mismo perfil.
create unique index if not exists evaluaciones_origen_unico
  on public.evaluaciones (origen_perfil_id, tipo)
  where origen_perfil_id is not null;
create unique index if not exists sesiones_origen_unico
  on public.sesiones (origen_perfil_id)
  where origen_perfil_id is not null;

-- updated_at automático
create or replace function public.tocar_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['atletas','sesiones','evaluaciones'] loop
    execute format('drop trigger if exists %I_updated_at on public.%I', t, t);
    execute format(
      'create trigger %I_updated_at before update on public.%I
       for each row execute function public.tocar_updated_at()', t, t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
--  2. SEGURIDAD (igual que `perfiles`: solo usuarios con sesión iniciada)
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array['atletas','sesiones','evaluaciones','competencias','aplicaciones'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s_solo_autenticados" on public.%I', t, t);
    execute format(
      'create policy "%s_solo_autenticados" on public.%I
       for all to authenticated using (true) with check (true)', t, t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
--  3. MIGRACIÓN DE LOS PERFILES EXISTENTES
-- ─────────────────────────────────────────────────────────────────────────

-- Normaliza un nombre para detectar que "María Fernández" y "Maria Fernandez"
-- son la misma persona: minúsculas, sin acentos, sin espacios de más.
create or replace function public.nombre_clave(txt text) returns text
language sql immutable as $$
  select nullif(
    translate(
      lower(regexp_replace(btrim(coalesce(txt,'')), '\s+', ' ', 'g')),
      'áàäâãéèëêíìïîóòöôõúùüûñç',
      'aaaaaeeeeiiiiooooouuuunc'
    ), '');
$$;

-- Clave "laxa": además ignora la h muda y confusiones frecuentes al escribir
-- (b/v, s/z/c, y/ll). Sirve SOLO para proponer posibles duplicados a revisar,
-- nunca para unirlos automáticamente: "Jonathan" y "Jonatan" pueden ser dos personas.
create or replace function public.nombre_clave_laxa(txt text) returns text
language sql immutable as $$
  select regexp_replace(
           translate(
             replace(replace(public.nombre_clave(txt), 'll', 'y'), 'h', ''),
             'bzcvq', 'vscvk'
           ), '(.)\1+', '\1', 'g');
$$;

-- Atletas que podrían ser la misma persona, para revisar a mano.
create or replace view public.posibles_duplicados as
  select public.nombre_clave_laxa(nombre) as clave,
         count(*)                          as cuantos,
         array_agg(nombre order by nombre) as nombres,
         array_agg(id    order by nombre)  as ids
    from public.atletas
   where public.nombre_clave_laxa(nombre) is not null
   group by 1
  having count(*) > 1;

do $$
declare
  p            record;
  v_atleta_id  uuid;
  v_sesion_id  uuid;
  v_clave      text;
  v_tiene_loehr boolean;
  v_invalidas  text[];
begin
  -- 3.1 Crear un atleta por cada persona distinta.
  --     Solo se miran los perfiles que todavía no fueron migrados, así una
  --     unificación hecha a mano no se deshace al volver a ejecutar el script.
  --     Se prefiere la escritura con acentos y, a igualdad, la más reciente.
  for p in
    select distinct on (public.nombre_clave(pf.nombre))
           public.nombre_clave(pf.nombre)                        as clave,
           btrim(regexp_replace(pf.nombre, '\s+', ' ', 'g'))     as nombre_limpio,
           pf.categoria, pf.cft
    from public.perfiles pf
    where public.nombre_clave(pf.nombre) is not null
      and not exists (select 1 from public.sesiones s where s.origen_perfil_id = pf.id)
    order by public.nombre_clave(pf.nombre),
             (length(pf.nombre) - length(regexp_replace(pf.nombre, '[^\x20-\x7E]', '', 'g'))) desc,
             coalesce(pf.fecha_aplicacion, pf.created_at::date) desc nulls last
  loop
    if not exists (
      select 1 from public.atletas a
      where public.nombre_clave(a.nombre) = p.clave
    ) then
      insert into public.atletas (nombre, sexo, deporte, organizacion, categoria, centro)
      values (
        p.nombre_limpio,
        case
          when p.categoria ilike '%femenino%' then 'Femenino'
          when p.categoria ilike '%masculino%' then 'Masculino'
        end,
        'Fútbol',
        'TDS - FFH',
        nullif(btrim(regexp_replace(coalesce(p.categoria,''), '(?i)\s*(masculino|femenino)\s*', '', 'g')), ''),
        p.cft
      );
    end if;
  end loop;

  -- 3.2 Completar fecha de nacimiento desde el perfil más reciente que la tenga.
  update public.atletas a
     set fecha_nacimiento = sub.fecha_nacimiento
    from (
      select distinct on (public.nombre_clave(nombre))
             public.nombre_clave(nombre) as clave, fecha_nacimiento
        from public.perfiles
       where fecha_nacimiento is not null
       order by public.nombre_clave(nombre),
                coalesce(fecha_aplicacion, created_at::date) desc nulls last
    ) sub
   where public.nombre_clave(a.nombre) = sub.clave
     and a.fecha_nacimiento is null;

  -- 3.3 Convertir cada perfil en una sesión + sus evaluaciones.
  for p in
    select * from public.perfiles
    order by coalesce(fecha_aplicacion, created_at::date), created_at
  loop
    v_clave := public.nombre_clave(p.nombre);
    continue when v_clave is null;

    -- Qué pruebas quedaron marcadas como inválidas en este perfil.
    v_invalidas := coalesce(p.invalidas, '{}'::text[]);
    if p.ci_diagnostico = 'PRUEBA INVÁLIDA' and not ('ci' = any(v_invalidas)) then
      v_invalidas := v_invalidas || 'ci'::text;
    end if;
    if p.temperamento in ('__invalida__','PRUEBA INVÁLIDA') and not ('temperamento' = any(v_invalidas)) then
      v_invalidas := v_invalidas || 'temperamento'::text;
    end if;

    -- Si este perfil ya se migró, se respeta el atleta al que quedó asignado
    -- (puede haber cambiado por una unificación manual).
    select id, atleta_id into v_sesion_id, v_atleta_id
      from public.sesiones where origen_perfil_id = p.id;

    if v_atleta_id is null then
      select id into v_atleta_id from public.atletas a
       where public.nombre_clave(a.nombre) = v_clave limit 1;
    end if;
    continue when v_atleta_id is null;

    if v_sesion_id is null then
      insert into public.sesiones
        (atleta_id, fecha, contexto, conclusion, recomendaciones, origen_perfil_id)
      values
        (v_atleta_id,
         coalesce(p.fecha_aplicacion, p.created_at::date),
         'Perfil psicológico',
         p.conclusion, p.recomendaciones, p.id)
      returning id into v_sesion_id;
    end if;

    -- CI — se migra si hay puntaje o si quedó marcada como prueba inválida.
    if p.ci is not null or p.ci_diagnostico is not null then
      insert into public.evaluaciones
        (atleta_id, tipo, fecha, sesion_id, datos, invalida, motivo_invalidez, origen_perfil_id)
      values (
        v_atleta_id, 'ci',
        coalesce(p.fecha_aplicacion, p.created_at::date), v_sesion_id,
        jsonb_strip_nulls(jsonb_build_object('ci', p.ci, 'diagnostico', p.ci_diagnostico)),
        'ci' = any(v_invalidas),
        case when 'ci' = any(v_invalidas)
             then 'Marcada como inválida en el registro original' end,
        p.id)
      on conflict do nothing;
    end if;

    -- Temperamento
    if p.temperamento is not null or p.temperamento_resumen is not null
       or 'temperamento' = any(v_invalidas) then
      insert into public.evaluaciones
        (atleta_id, tipo, fecha, sesion_id, datos, interpretacion,
         invalida, motivo_invalidez, origen_perfil_id)
      values (
        v_atleta_id, 'temperamento',
        coalesce(p.fecha_aplicacion, p.created_at::date), v_sesion_id,
        -- El valor interno "__invalida__" no se guarda: la marca va en `invalida`.
        case when 'temperamento' = any(v_invalidas) then '{}'::jsonb
             else jsonb_strip_nulls(jsonb_build_object('temperamento', p.temperamento)) end,
        p.temperamento_resumen,
        'temperamento' = any(v_invalidas),
        case when 'temperamento' = any(v_invalidas)
             then 'Marcada como inválida en el registro original' end,
        p.id)
      on conflict do nothing;
    end if;

    -- Ansiedad (estado y/o rasgo, con su interpretación)
    if p.ansiedad_estado is not null or p.ansiedad_rasgo is not null
       or 'ansiedad' = any(v_invalidas) then
      insert into public.evaluaciones
        (atleta_id, tipo, fecha, sesion_id, datos, interpretacion,
         invalida, motivo_invalidez, origen_perfil_id)
      values (
        v_atleta_id, 'ansiedad',
        coalesce(p.fecha_aplicacion, p.created_at::date), v_sesion_id,
        jsonb_strip_nulls(jsonb_build_object(
          'estado',       p.ansiedad_estado,
          'estado_nivel', p.ansiedad_estado_nivel,
          'rasgo',        p.ansiedad_rasgo,
          'rasgo_nivel',  p.ansiedad_rasgo_nivel)),
        p.ansiedad_interpretacion,
        'ansiedad' = any(v_invalidas),
        case when 'ansiedad' = any(v_invalidas)
             then 'Marcada como inválida en el registro original' end,
        p.id)
      on conflict do nothing;
    end if;

    -- Loehr — solo si tiene al menos una escala cargada.
    v_tiene_loehr := coalesce(p.loehr_ac,0) + coalesce(p.loehr_en,0)
                   + coalesce(p.loehr_cat,0) + coalesce(p.loehr_cvi,0)
                   + coalesce(p.loehr_nm,0) + coalesce(p.loehr_ep,0)
                   + coalesce(p.loehr_act,0) > 0;
    if v_tiene_loehr or 'loehr' = any(v_invalidas) then
      insert into public.evaluaciones
        (atleta_id, tipo, fecha, sesion_id, datos, interpretacion,
         invalida, motivo_invalidez, origen_perfil_id)
      values (
        v_atleta_id, 'loehr',
        coalesce(p.fecha_aplicacion, p.created_at::date), v_sesion_id,
        jsonb_build_object(
          'escalas', jsonb_build_object(
            'AC',  coalesce(p.loehr_ac,0),  'EN',  coalesce(p.loehr_en,0),
            'CAT', coalesce(p.loehr_cat,0), 'CVI', coalesce(p.loehr_cvi,0),
            'NM',  coalesce(p.loehr_nm,0),  'EP',  coalesce(p.loehr_ep,0),
            'ACT', coalesce(p.loehr_act,0))),
        p.loehr_interpretacion,
        'loehr' = any(v_invalidas),
        case when 'loehr' = any(v_invalidas)
             then 'Marcada como inválida en el registro original' end,
        p.id)
      on conflict do nothing;
    end if;
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
--  3b. UNIFICAR DOS ATLETAS QUE SON LA MISMA PERSONA
-- ─────────────────────────────────────────────────────────────────────────

-- Pasa todo lo del atleta "repetido" al atleta "bueno" y borra el repetido.
-- Se usa desde la app, o a mano:
--   select public.unificar_atletas('<id-del-bueno>', '<id-del-repetido>');
create or replace function public.unificar_atletas(
  id_bueno uuid, id_repetido uuid
) returns text
language plpgsql security invoker as $$
declare
  v_nombre_rep  text;
  v_evals       int;
  v_ses         int;
begin
  if id_bueno = id_repetido then
    raise exception 'Son el mismo atleta.';
  end if;

  select nombre into v_nombre_rep from public.atletas where id = id_repetido;
  if v_nombre_rep is null then
    raise exception 'No existe el atleta a unificar (%).', id_repetido;
  end if;
  if not exists (select 1 from public.atletas where id = id_bueno) then
    raise exception 'No existe el atleta destino (%).', id_bueno;
  end if;

  update public.evaluaciones set atleta_id = id_bueno where atleta_id = id_repetido;
  get diagnostics v_evals = row_count;
  update public.sesiones    set atleta_id = id_bueno where atleta_id = id_repetido;
  get diagnostics v_ses = row_count;

  -- Completa en el atleta bueno los datos que solo tenía el repetido.
  update public.atletas a
     set fecha_nacimiento = coalesce(a.fecha_nacimiento, r.fecha_nacimiento),
         sexo             = coalesce(a.sexo,             r.sexo),
         deporte          = coalesce(a.deporte,          r.deporte),
         organizacion     = coalesce(a.organizacion,     r.organizacion),
         categoria        = coalesce(a.categoria,        r.categoria),
         posicion         = coalesce(a.posicion,         r.posicion),
         centro           = coalesce(a.centro,           r.centro),
         notas            = coalesce(a.notas,            r.notas)
    from public.atletas r
   where a.id = id_bueno and r.id = id_repetido;

  delete from public.atletas where id = id_repetido;

  return format('Unificado "%s": se movieron %s evaluaciones y %s sesiones.',
                v_nombre_rep, v_evals, v_ses);
end $$;

-- ─────────────────────────────────────────────────────────────────────────
--  4. VERIFICACIÓN
-- ─────────────────────────────────────────────────────────────────────────

-- 4.1 Resumen de la migración
select 'perfiles originales'      as concepto, count(*)::text as valor from public.perfiles
union all
select 'atletas creados',          count(*)::text from public.atletas
union all
select 'sesiones creadas',         count(*)::text from public.sesiones
union all
select 'evaluaciones creadas',     count(*)::text from public.evaluaciones
union all
select '  · de tipo ' || tipo,     count(*)::text from public.evaluaciones group by tipo
order by 1;

-- 4.2 Atletas que podrían ser la misma persona (revisar y unificar a mano)
select nombres as "revisar: posible misma persona" from public.posibles_duplicados;

-- 4.3 Atletas sin nombre real, para corregir
select id, nombre as "revisar: nombre incompleto"
  from public.atletas
 where public.nombre_clave(nombre) in ('sin nombre','atleta','-')
    or length(public.nombre_clave(nombre)) < 4;
