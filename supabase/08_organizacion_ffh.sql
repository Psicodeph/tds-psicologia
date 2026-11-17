-- ============================================================================
--  08 - Corregir el nombre de la organización
--
--  La migración cargó los atletas como "TDS - FENAFUTH". El nombre correcto
--  es FFH (Federación de Fútbol de Honduras).
--
--  Se puede ejecutar más de una vez.
-- ============================================================================

update public.atletas
   set organizacion = 'TDS - FFH'
 where organizacion = 'TDS - FENAFUTH';

select organizacion, count(*) as atletas
  from public.atletas
 group by organizacion
 order by 2 desc;
