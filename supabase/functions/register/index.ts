// POST /functions/v1/register
// Body: { "email", "password", "full_name", "role": "FATHER" | "ADMIN" }
//
// Admin-only: creates an Auth user + profile (role from metadata via
// handle_new_user). Public self-signup is disabled (enable_signup = false).

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/supabaseClient.ts";

const ALLOWED_ROLES = new Set(["FATHER", "ADMIN"]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const admin = await requireAdmin(req);
  if (!admin.ok) return admin.response;

  let body: {
    email?: string;
    password?: string;
    full_name?: string;
    role?: string;
  };
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400);
  }

  const email = body.email?.trim();
  const password = body.password;
  const fullName = body.full_name?.trim();
  const role = body.role?.trim();

  if (!email || !password || !fullName || !role) {
    return errorResponse("email, password, full_name, and role are required", 400);
  }

  if (!ALLOWED_ROLES.has(role)) {
    return errorResponse("role must be FATHER or ADMIN", 400);
  }

  if (password.length < 6) {
    return errorResponse("password must be at least 6 characters", 400);
  }

  const { data, error } = await admin.service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      full_name: fullName,
      role,
    },
  });

  if (error || !data.user) {
    return errorResponse(error?.message ?? "Failed to create user", 400);
  }

  return jsonResponse(
    {
      success: true,
      data: {
        id: data.user.id,
        email: data.user.email,
        full_name: fullName,
        role,
      },
    },
    201,
  );
});
