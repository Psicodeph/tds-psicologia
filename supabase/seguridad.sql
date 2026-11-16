-- Seguridad de la base de datos (Row Level Security).
-- Ejecutar en Supabase → SQL Editor, DESPUÉS de crear los usuarios en Authentication → Users
-- y de publicar la versión de la app con login por usuario.
--
-- Usuarios: en la app se escribe solo el usuario (ej. "practicante1"). En Supabase se crea como
-- "practicante1@tds.example.com" con "Auto confirm user" marcado. No hace falta un correo real.
--
-- Con esto, la clave "anon" que está en el código ya no permite leer ni modificar nada:
-- solo un usuario que inició sesión puede ver, crear, editar o borrar perfiles.

-- 1) Borrar todas las reglas anteriores (por ejemplo "acceso_abierto"). Las reglas se suman:
--    si queda una abierta, la tabla sigue abierta aunque se agreguen otras.
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename in ('perfiles', 'configuracion')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- 2) Perfiles: solo usuarios autenticados.
alter table public.perfiles enable row level security;
create policy "perfiles_solo_autenticados" on public.perfiles
  for all to authenticated using (true) with check (true);

-- 3) Configuración: RLS activo y sin reglas = nadie la puede leer desde la app.
--    La contraseña vieja ya no se usa.
alter table public.configuracion enable row level security;
delete from public.configuracion where clave = 'password';

-- 4) Verificación: configuracion → true, (ninguna); perfiles → true, perfiles_solo_autenticados (authenticated).
select t.tablename, t.rowsecurity,
       coalesce(string_agg(p.policyname || ' (' || array_to_string(p.roles, ',') || ')', ', '), '(ninguna)') as reglas
from pg_tables t
left join pg_policies p on p.schemaname = t.schemaname and p.tablename = t.tablename
where t.schemaname = 'public' and t.tablename in ('perfiles', 'configuracion')
group by t.tablename, t.rowsecurity;
