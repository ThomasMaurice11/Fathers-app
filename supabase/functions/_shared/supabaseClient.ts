import { createClient, type SupabaseClient, type User } from "https://esm.sh/@supabase/supabase-js@2";
import { errorResponse } from "./cors.ts";

/**
 * Creates a Supabase client that acts AS THE CALLING FATHER, using the
 * JWT from the incoming request's Authorization header. RLS policies
 * apply exactly as they would from the frontend - this function grants
 * no extra privileges.
 */
export function getUserClient(req: Request) {
  const authHeader = req.headers.get("Authorization") ?? "";

  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    }
  );
}

/**
 * Service-role client for privileged Auth Admin operations (e.g. createUser).
 * Bypasses RLS — only use after the caller has been authorized as ADMIN.
 */
export function getServiceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
    }
  );
}

export async function getAuthenticatedUser(req: Request) {
  const supabase = getUserClient(req);
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return { supabase, user: null };
  }
  return { supabase, user };
}

type RequireAdminOk = {
  ok: true;
  user: User;
  supabase: SupabaseClient;
  service: SupabaseClient;
  role: "ADMIN";
};

type RequireAdminErr = {
  ok: false;
  response: Response;
};

/**
 * Ensures the caller is signed in and profiles.role = ADMIN.
 * Uses the service client to read the profile (avoids relying on RLS
 * for the admin gate itself).
 */
export async function requireAdmin(req: Request): Promise<RequireAdminOk | RequireAdminErr> {
  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) {
    return { ok: false, response: errorResponse("Unauthorized", 401) };
  }

  const service = getServiceClient();
  const { data: profile, error } = await service
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();

  if (error) {
    return { ok: false, response: errorResponse("Failed to verify admin role", 500) };
  }

  if (!profile || profile.role !== "ADMIN") {
    return { ok: false, response: errorResponse("Admin access required", 403) };
  }

  return { ok: true, user, supabase, service, role: "ADMIN" };
}
