// POST /functions/v1/change-password
// Body: { "current_password": "...", "new_password": "..." }
//
// Logged-in user changes password after verifying the current one.
// verify_jwt = true.
//
// Password update uses Auth REST PUT /auth/v1/user with the request
// Bearer token. supabase.auth.updateUser() fails here with
// "Auth session missing!" because the Edge Function client has no
// in-memory session.

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const { user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  let body: { current_password?: string; new_password?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400);
  }

  const currentPassword = body.current_password;
  const newPassword = body.new_password;

  if (!currentPassword || !newPassword) {
    return errorResponse("current_password and new_password are required", 400);
  }
  if (newPassword.length < 6) {
    return errorResponse("new_password must be at least 6 characters", 400);
  }
  if (!user.email) {
    return errorResponse("User email is missing", 400);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const verifyRes = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email: user.email, password: currentPassword }),
  });

  if (!verifyRes.ok) {
    return errorResponse("Current password is incorrect", 401);
  }

  const updateRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
    method: "PUT",
    headers: {
      apikey: anonKey,
      Authorization: authHeader,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ password: newPassword }),
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
    message: "Password changed successfully.",
  });
});
