// POST /functions/v1/login
// Body: { "email": "...", "password": "..." }
//
// Thin wrapper around Supabase Auth's password grant, so you can get a
// fresh access_token from Swagger UI / Postman without a separate curl
// call to the Auth REST API. Unlike every other function in this repo,
// this one does NOT require a Bearer token (there isn't one yet) — see
// `verify_jwt = false` for "login" in supabase/config.toml.

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  let body: { email?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400);
  }

  if (!body.email || !body.password) {
    return errorResponse("email and password are required", 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const authRes = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email: body.email, password: body.password }),
  });

  const data = await authRes.json();

  if (!authRes.ok) {
    return errorResponse(data.error_description ?? data.msg ?? "Login failed", authRes.status);
  }

  // Load display name from profiles (father_name)
  let fatherName: string | null = null;
  if (data.user?.id) {
    const profileRes = await fetch(
      `${supabaseUrl}/rest/v1/profiles?id=eq.${data.user.id}&select=full_name`,
      {
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${data.access_token}`,
        },
      },
    );
    if (profileRes.ok) {
      const profiles = await profileRes.json();
      fatherName = profiles?.[0]?.full_name ?? null;
    }
  }

  return jsonResponse({
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    token_type: data.token_type,
    expires_in: data.expires_in,
    expires_at: data.expires_at,
    user: {
      id: data.user?.id,
      email: data.user?.email,
      father_name: fatherName,
    },
  });
});
