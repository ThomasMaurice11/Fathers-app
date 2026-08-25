import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
