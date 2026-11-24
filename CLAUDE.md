# App de Melany Ordóñez — Psicología del Deporte

Plataforma de evaluación y seguimiento psicológico. Centrada en el atleta, con
instrumentos psicométricos registrados por fecha, histórico por prueba,
monitoreo de grupo y consulta con IA. Nació para el programa TDS de la FFH y
sostiene también otros clubes, otros deportes y atletas particulares.

Stack: HTML plano sin build + Supabase (Postgres, Auth, RLS) + Vercel.

Antes de diseñar o cambiar lógica del dominio, leer `CONTEXTO_TDS.md`: explica
la metodología, la pirámide por categoría, el sistema de conceptos, el modelo
de aplicación 2027 y la capa neurocognitiva por posición. Es un documento vivo
y manda sobre los supuestos.

## Reglas del dominio

Son decisiones ya tomadas. No rehacerlas sin pedirlo.

- **La federación es FFH** (Federación de Fútbol de Honduras), no FENAFUTH.
  FENAFUTH es el nombre anterior.
- **"Atleta", no "jugador"**, en todo lo que ve el usuario: no todos los
  deportes que usa la plataforma hablan de jugadores. Dentro de la metodología
  TDS, que es fútbol, "jugador" sí corresponde.
- **TDS es un programa de la FFH donde Melany trabaja; no es suyo.** El pie de
  los informes lleva su nombre o su logo y la fecha. No lleva la marca TDS ni
  el lugar.
- **Siempre tiene que haber espacio para escribir**: interpretación por prueba,
  conclusión y recomendaciones. Un perfil sin eso está incompleto y la app lo
  marca como tal.
- **Una prueba inválida es un dato, no un hueco.** La invalidez informa a nivel
  diagnóstico, sea por un rasgo de personalidad o por falta de comprensión de
  la consigna. Se cuenta, se muestra y entra en el contexto que lee la IA; lo
  que no entra son sus puntajes.
- **La IA razona sobre el conjunto**: perfil completo más reciente, historia
  del atleta y cruce entre instrumentos. Ningún dato aislado sostiene una
  conclusión.
- **El CI es el dato más sensible.** Va sin marcar por defecto en los informes
  para atleta o entrenador.
- **La tabla `perfiles` no se toca**: es el respaldo de los datos originales.

## Cómo se trabaja el repo

- Páginas HTML sueltas, sin framework ni paso de build. Cada página se vale por
  sí misma.
- Migraciones SQL numeradas en `supabase/`, idempotentes: se tienen que poder
  correr más de una vez sin romper nada.
- Las pruebas son Playwright con Supabase simulado, fuera del repo.
- Comentarios y mensajes de commit en español, explicando el porqué y no el qué.
