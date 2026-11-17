-- ============================================================================
--  11 - Atletas repetidos con el nombre escrito distinto
--
--  La comparación anterior solo resolvía acentos, espacios y la h muda. No
--  alcanzaba para errores de tipeo dentro de la palabra, como "Leonel" contra
--  "Lionel" o "Lezama" contra "Lezma".
--
--  Esta versión compara palabra por palabra: dos nombres son candidatos si la
--  mayoría de sus palabras empiezan igual. SOLO MUESTRA: unir dos atletas es
--  una decisión clínica, no la toma el script.
-- ============================================================================

-- Las palabras del nombre, normalizadas y recortadas a sus primeras letras.
create or replace function public.raices_nombre(txt text) returns text[]
language sql immutable as $$
  select array_agg(substr(p, 1, 3) order by substr(p, 1, 3))
    from unnest(string_to_array(public.nombre_clave(txt), ' ')) p
   where length(p) > 1;   -- se ignoran iniciales sueltas
$$;

-- Cuántas palabras comparten dos nombres, sobre el total del más corto.
create or replace function public.parecido_nombres(a text, b text) returns numeric
language sql immutable as $$
  select case
    when ra is null or rb is null or array_length(ra,1) is null or array_length(rb,1) is null then 0
    else (
      select count(*)::numeric from (
        select unnest(ra) intersect all select unnest(rb)
      ) c
    ) / least(array_length(ra,1), array_length(rb,1))
  end
  from (select public.raices_nombre(a) as ra, public.raices_nombre(b) as rb) t;
$$;

drop view if exists public.posibles_duplicados;
create view public.posibles_duplicados as
  select a.id    as id_a,  a.nombre as nombre_a,
         b.id    as id_b,  b.nombre as nombre_b,
         round(public.parecido_nombres(a.nombre, b.nombre) * 100) as parecido,
         (select count(*) from public.evaluaciones e where e.atleta_id = a.id) as evaluaciones_a,
         (select count(*) from public.evaluaciones e where e.atleta_id = b.id) as evaluaciones_b
    from public.atletas a
    join public.atletas b
      on a.id < b.id
     and public.parecido_nombres(a.nombre, b.nombre) >= 0.6
     -- Dos personas distintas pueden llamarse casi igual. Si el sexo o la
     -- fecha de nacimiento se contradicen, no son la misma y no se proponen.
     and (a.sexo is null or b.sexo is null or a.sexo = b.sexo)
     and (a.fecha_nacimiento is null or b.fecha_nacimiento is null
          or a.fecha_nacimiento = b.fecha_nacimiento)
     -- Un apellido en común no alcanza: tienen que coincidir al menos dos palabras.
     and (select count(*) from (
            select unnest(public.raices_nombre(a.nombre))
            intersect all
            select unnest(public.raices_nombre(b.nombre))
          ) c) >= 2
   order by 5 desc, 2;

-- ─────────────────────────────────────────────────────────────────────────
--  Revisar estos pares. Si son la misma persona, unirlos con:
--
--    select public.unificar_atletas('<id del nombre a conservar>',
--                                   '<id del nombre repetido>');
--
--  Mueve todo el historial al atleta que se conserva y borra el repetido.
--  La tabla `perfiles` queda intacta, así que nada se pierde.
-- ─────────────────────────────────────────────────────────────────────────

select nombre_a, nombre_b, parecido || '%' as "se parecen",
       evaluaciones_a || ' / ' || evaluaciones_b as "evaluaciones",
       'select public.unificar_atletas(''' || id_a || ''', ''' || id_b || ''');' as "para unirlos"
  from public.posibles_duplicados;
