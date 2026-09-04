// POST /functions/v1/forgot-password
// Body: { "email": "..." }
//
// Sends a password-reset email via Supabase Auth. Always returns a
// generic success message so callers cannot probe whether an email
// is registered. verify_jwt = false (no token yet).

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  let body: { email?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400);
  }

  const email = body.email?.trim();
  if (!email) {
    return errorResponse("email is required", 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false } },
  );

  const redirectTo = Deno.env.get("SITE_URL") ?? "http://localhost:5173";

  // Intentionally ignore Auth errors in the response — do not leak
  // whether the address exists. Real delivery still depends on the
  // project's Auth email / SMTP settings.
  await supabase.auth.resetPasswordForEmail(email, { redirectTo });

  return jsonResponse({
    success: true,
    message: "If an account exists for that email, a reset link has been sent.",
  });
});
