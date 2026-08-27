// GET /functions/v1/confession-reminders
// GET /functions/v1/confession-reminders?unread_only=true

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return errorResponse("Method not allowed", 405);
  }

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const url = new URL(req.url);
  const unreadOnly = url.searchParams.get("unread_only") !== "false";

  const { data, error } = await supabase.rpc("get_confession_reminders", {
    p_unread_only: unreadOnly,
  });

  if (error) return errorResponse(error.message, 400);

  return jsonResponse({ data });
});
