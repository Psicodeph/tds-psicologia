-- ============================================================================
--  15 - Accesos de toma
--
--  Un atleta no es usuario de la app: darle usuario le daría acceso a datos
--  sensibles de todo el plantel. Entra por una puerta aparte, que solo sirve
--  para cargar una prueba y no deja leer nada.
--
--  Quien aplica recibe un código (o un QR, que es el mismo código dentro de
--  un enlace). Hay dos clases:
--
--    'atleta'  El entrenador aplica a un solo atleta. Dos aperturas, una por
--              si entra por error, y se cierra al enviar.
--    'sesion'  La psicóloga aplica a varios seguidos en una jornada. Vale ese
--              día y recorre una lista armada de antemano.
--
--  La clave del diseño: `accesos` tiene RLS y ninguna regla para `anon`, así
--  que la clave pública de la app no puede ni leerla. Todo pasa por dos
--  funciones `security definer`, que son la única superficie expuesta y
--  validan en el servidor. Un código no puede consultar resultados, fichas,
--  ni datos de otros atletas: solo lo justo para identificar a quién se le
--  está tomando la prueba.
--
--  Se puede ejecutar más de una vez.
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists public.accesos (
  id              uuid primary key default gen_random_uuid(),
  codigo          text not null unique,
  tipo            text not null check (tipo in ('atleta','sesion')),
  prueba          text not null default 'stroop',
  atleta_id       uuid references public.atletas(id) on delete cascade,
  plantel         uuid[] not null default '{}',
  etiqueta        text,                    -- "Sub-14 Tegucigalpa", para reconocerlo
  aplicada_por    text,                    -- quién va a aplicar, si se sabe de antemano
  aperturas       integer not null default 0,
  max_aperturas   integer,                 -- null = sin límite (las sesiones)
  vence           timestamptz not null,
  consumido_en    timestamptz,             -- cuándo se envió la prueba
  anulado         boolean not null default false,
  created_at      timestamptz not null default now()
);

-- Un acceso de atleta apunta a un atleta; uno de sesión, a una lista.
do $$ begin
  alter table public.accesos add constraint accesos_destino_coherente check (
    (tipo = 'atleta' and atleta_id is not null) or
    (tipo = 'sesion' and array_length(plantel, 1) is not null)
  );
exception when duplicate_object then null; end $$;

create index if not exists accesos_vence on public.accesos (vence);

-- Solo la psicóloga, con sesión iniciada, genera y revisa códigos.
-- Para `anon` no hay ninguna regla, así que la tabla le es invisible.
alter table public.accesos enable row level security;
drop policy if exists "accesos_solo_autenticados" on public.accesos;
create policy "accesos_solo_autenticados" on public.accesos
  for all to authenticated using (true) with check (true);

-- ─────────────────────────────────────────────────────────────────────────
--  Generar un código
-- ─────────────────────────────────────────────────────────────────────────

-- Alfabeto sin caracteres que se confundan al dictarlos o tipearlos:
-- sin I, L, O, U, 0 ni 1. Ocho posiciones sobre 30 símbolos.
create or replace function public.codigo_nuevo() returns text
language plpgsql as $$
declare
  alfabeto constant text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  intento text;
  i integer;
begin
  loop
    intento := '';
    for i in 1..8 loop
      intento := intento || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1);
    end loop;
    exit when not exists (select 1 from public.accesos where codigo = intento);
  end loop;
  return intento;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
--  Abrir un acceso
--
--  Devuelve lo mínimo para saber a quién se le toma la prueba. Nunca
--  devuelve resultados ni datos de atletas fuera del alcance del código.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.abrir_acceso(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a public.accesos;
  atletas_json jsonb;
begin
  select * into a from public.accesos
   where codigo = upper(btrim(p_codigo)) for update;

  if not found then        return jsonb_build_object('ok', false, 'motivo', 'inexistente'); end if;
  if a.anulado then        return jsonb_build_object('ok', false, 'motivo', 'anulado'); end if;
  if a.vence < now() then  return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  if a.consumido_en is not null then
    return jsonb_build_object('ok', false, 'motivo', 'usado');
  end if;
  if a.max_aperturas is not null and a.aperturas >= a.max_aperturas then
    return jsonb_build_object('ok', false, 'motivo', 'gastado');
  end if;

  -- La apertura se cuenta acá, no al enviar: la toma es corrida y si se
  -- interrumpe hay que rehacerla entera con un código nuevo.
  update public.accesos set aperturas = aperturas + 1 where id = a.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'nombre', x.nombre, 'fecha_nacimiento', x.fecha_nacimiento,
           'categoria', x.categoria, 'posicion', x.posicion
         ) order by x.nombre), '[]'::jsonb)
    into atletas_json
    from public.atletas x
   where (a.tipo = 'atleta' and x.id = a.atleta_id)
      or (a.tipo = 'sesion' and x.id = any(a.plantel));

  return jsonb_build_object(
    'ok', true, 'tipo', a.tipo, 'prueba', a.prueba, 'etiqueta', a.etiqueta,
    'aplicada_por', a.aplicada_por, 'vence', a.vence,
    'aperturas_restantes', case when a.max_aperturas is null then null
                                else a.max_aperturas - a.aperturas - 1 end,
    'atletas', atletas_json);
end $$;

-- ─────────────────────────────────────────────────────────────────────────
--  Guardar una prueba
--
--  El atleta tiene que estar dentro del alcance del código. Los datos que el
--  atleta declara sobre sí mismo (nombre, fecha de nacimiento) NO modifican
--  su ficha: quedan guardados dentro de la evaluación para que la psicóloga
--  los confirme. Así un código filtrado no puede alterar datos del plantel.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.guardar_prueba(
  p_codigo text, p_atleta_id uuid, p_datos jsonb,
  p_aplicada_por text default null, p_invalida boolean default false,
  p_motivo_invalidez text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a public.accesos;
  nueva uuid;
begin
  select * into a from public.accesos
   where codigo = upper(btrim(p_codigo)) for update;

  if not found then        return jsonb_build_object('ok', false, 'motivo', 'inexistente'); end if;
  if a.anulado then        return jsonb_build_object('ok', false, 'motivo', 'anulado'); end if;
  if a.vence < now() then  return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  if a.consumido_en is not null then
    return jsonb_build_object('ok', false, 'motivo', 'usado');
  end if;

  if not ((a.tipo = 'atleta' and p_atleta_id = a.atleta_id)
       or (a.tipo = 'sesion' and p_atleta_id = any(a.plantel))) then
    return jsonb_build_object('ok', false, 'motivo', 'fuera_de_alcance');
  end if;

  insert into public.evaluaciones (atleta_id, tipo, fecha, datos, contexto,
                                   aplicada_por, invalida, motivo_invalidez)
  values (p_atleta_id, a.prueba, current_date,
          coalesce(p_datos, '{}'::jsonb), a.etiqueta,
          coalesce(nullif(btrim(coalesce(p_aplicada_por, '')), ''), a.aplicada_por),
          coalesce(p_invalida, false), p_motivo_invalidez)
  returning id into nueva;

  -- Un código de atleta sirve para una sola toma. Uno de sesión sigue vivo
  -- hasta que vence, porque recorre a todo el grupo.
  if a.tipo = 'atleta' then
    update public.accesos set consumido_en = now() where id = a.id;
  end if;

  return jsonb_build_object('ok', true, 'evaluacion_id', nueva);
end $$;

-- `anon` solo puede llamar a estas dos funciones. Nada más de la base le
-- queda al alcance.
--
-- Ojo con el orden y con a quién se le revoca: Supabase concede EXECUTE sobre
-- las funciones de `public` a `anon` de forma explícita, y además lo deja como
-- privilegio por omisión para las funciones futuras. Revocarle a PUBLIC no
-- alcanza, porque la concesión explícita a `anon` sobrevive. Hay que nombrarlo.
revoke all on function public.abrir_acceso(text) from public, anon, authenticated;
revoke all on function public.guardar_prueba(text, uuid, jsonb, text, boolean, text)
  from public, anon, authenticated;
revoke all on function public.codigo_nuevo() from public, anon, authenticated;

grant execute on function public.abrir_acceso(text) to anon, authenticated;
grant execute on function public.guardar_prueba(text, uuid, jsonb, text, boolean, text)
  to anon, authenticated;
-- Generar códigos es tarea de la psicóloga, no de quien aplica.
grant execute on function public.codigo_nuevo() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
--  Verificación
-- ─────────────────────────────────────────────────────────────────────────

select 'tabla accesos' as que,
       (select count(*) from information_schema.tables
         where table_schema = 'public' and table_name = 'accesos')::text as valor
union all
select 'reglas para anon en accesos (debe ser 0)',
       (select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'accesos'
           and 'anon' = any(roles))::text
union all
select 'funciones que anon puede llamar (deben ser las dos de la toma)',
       (select coalesce(string_agg(p.proname, ', ' order by p.proname), '(ninguna)')
          from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and has_function_privilege('anon', p.oid, 'execute'))
union all
select 'anon puede generar códigos (debe ser false)',
       has_function_privilege('anon', 'public.codigo_nuevo()', 'execute')::text;
