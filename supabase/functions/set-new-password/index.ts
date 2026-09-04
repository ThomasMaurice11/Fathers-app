// POST /functions/v1/set-new-password
// Body: { "password": "..." }
//
// Sets a new password for the caller. Used after the recovery email
// link establishes a session (recovery JWT), or with any valid JWT.
// verify_jwt = true.
//
// Uses Auth REST PUT /auth/v1/user with the request Bearer token.
// supabase.auth.updateUser() fails here with "Auth session missing!"
// because the Edge Function client has no in-memory session.

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const { user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  let body: { password?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400);
  }

  const password = body.password;
  if (!password) {
    return errorResponse("password is required", 400);
  }
  if (password.length < 6) {
    return errorResponse("password must be at least 6 characters", 400);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const updateRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
    method: "PUT",
    headers: {
      apikey: anonKey,
      Authorization: authHeader,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ password }),
  });

  if (!updateRes.ok) {
    const data = await updateRes.json().catch(() => ({}));
    return errorResponse(
      data.msg ?? data.error_description ?? data.error ?? "Failed to update password",
      updateRes.status,
    );
  }

  return jsonResponse({
    success: true,
    message: "Password updated successfully.",
  });
});
