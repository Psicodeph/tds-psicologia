// Proxy hacia la API de Anthropic. Solo responde a usuarios con sesión válida de Supabase,
// así nadie de afuera puede usar la clave de la API.
// Sin cabeceras CORS: el navegador solo permite llamarlo desde el mismo dominio de la app.
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://esbmtenfcjbrrocrnfep.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVzYm10ZW5mY2picnJvY3JuZmVwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1MTIxNjcsImV4cCI6MjA5NjA4ODE2N30.9N-xdmGwcuUF3EBYsjB4bEMeWbXVjmWZbizIeUudEkA';
const MAX_PROMPT_CHARS = 400000;

async function usuarioValido(authHeader) {
  const token = (authHeader || '').replace(/^Bearer\s+/i, '');
  if (!token) return false;
  try {
    const r = await fetch(SUPABASE_URL + '/auth/v1/user', {
      headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + token },
    });
    return r.ok;
  } catch (e) {
    console.error(e);
    return false;
  }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  if (!(await usuarioValido(req.headers.authorization))) {
    return res.status(401).json({ error: 'No autorizado' });
  }

  const { prompt } = req.body || {};
  if (!prompt || typeof prompt !== 'string') return res.status(400).json({ error: 'Falta el prompt' });
  if (prompt.length > MAX_PROMPT_CHARS) return res.status(413).json({ error: 'La consulta es demasiado larga' });

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 2000,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    const data = await response.json();
    if (!response.ok) {
      console.error(data);
      return res.status(502).json({ error: 'La IA no pudo responder. Intentá de nuevo.' });
    }
    return res.status(200).json(data);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Error al conectar con la IA' });
  }
}
