// POST /functions/v1/set-new-password
// Body: { "password": "..." }
//
// Sets a new password for the caller. Used after the recovery email
// link establishes a session (recovery JWT), or with any valid JWT.
// verify_jwt = true.

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const { supabase, user } = await getAuthenticatedUser(req);
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

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    return errorResponse(error.message ?? "Failed to update password", 400);
  }

  return jsonResponse({
    success: true,
    message: "Password updated successfully.",
  });
});
