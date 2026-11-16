-- ============================================================================
--  Revisión después de migrar: todo en una sola lista.
--  Pegar en Supabase → SQL Editor y ejecutar.
-- ============================================================================
select seccion, detalle from (

  -- Cuántas evaluaciones quedaron de cada prueba
  select 1 as orden, '1. EVALUACIONES POR PRUEBA' as seccion,
         tipo || ': ' || count(*)::text as detalle
    from public.evaluaciones group by tipo

  union all
  -- Atletas que podrían ser la misma persona escrita distinto
  select 2, '2. REVISAR: ¿misma persona?',
         array_to_string(nombres, '   |   ')
    from public.posibles_duplicados

  union all
  -- Nombres incompletos o genéricos
  select 3, '3. REVISAR: nombre incompleto',
         nombre || '   (id: ' || id::text || ')'
    from public.atletas
   where public.nombre_clave(nombre) in ('sin nombre','atleta','-')
      or length(public.nombre_clave(nombre)) < 4

  union all
  -- Atletas con más de una evaluación de la misma prueba (ya tienen historial)
  select 4, '4. Atletas con historial',
         a.nombre || ' — ' || e.tipo || ' x' || count(*)::text
    from public.evaluaciones e
    join public.atletas a on a.id = e.atleta_id
   group by a.nombre, e.tipo
  having count(*) > 1

  union all
  -- Perfiles que no se pudieron migrar (sin nombre utilizable)
  select 5, '5. Perfiles sin migrar (sin nombre)',
         count(*)::text || ' de ' || (select count(*) from public.perfiles)::text
    from public.perfiles p
   where not exists (select 1 from public.sesiones s where s.origen_perfil_id = p.id)
  having count(*) > 0

) t
order by orden, detalle;
