-- Seguridad de la base de datos (Row Level Security).
-- Ejecutar en Supabase → SQL Editor, DESPUÉS de crear el usuario en Authentication → Users
-- y de publicar la versión de la app con login por correo.
--
-- Con esto, la clave "anon" que está en el código ya no permite leer ni modificar nada:
-- solo un usuario que inició sesión puede ver, crear, editar o borrar perfiles.

-- 1) Perfiles: solo usuarios autenticados.
alter table public.perfiles enable row level security;

drop policy if exists "perfiles_solo_autenticados" on public.perfiles;
create policy "perfiles_solo_autenticados"
  on public.perfiles
  for all
  to authenticated
  using (true)
  with check (true);

-- 2) Configuración: la contraseña vieja ya no se usa. RLS activo y sin políticas = nadie la puede leer desde la app.
alter table public.configuracion enable row level security;

-- Opcional: borrar la contraseña vieja (la app ya no la consulta).
-- delete from public.configuracion where clave = 'password';

-- Verificación: las dos filas tienen que decir rowsecurity = true.
select tablename, rowsecurity from pg_tables
where schemaname = 'public' and tablename in ('perfiles', 'configuracion');
