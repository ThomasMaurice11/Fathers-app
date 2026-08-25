// GET /functions/v1/stages -> list all predefined stages
// Read-only: there is no write route, since stages must never be
// created/updated/deleted by fathers (also enforced by RLS).

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return errorResponse("Method not allowed", 405);

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const { data, error } = await supabase.from("stages").select("*").order("id");
  if (error) return errorResponse(error.message, 400);

  return jsonResponse({ data });
});
