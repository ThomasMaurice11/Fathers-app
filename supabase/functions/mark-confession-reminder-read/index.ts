// POST /functions/v1/mark-confession-reminder-read/:childId
//
// (Supabase routes all requests to a function by its folder name; the
// child id is read from the trailing path segment.)

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";
import { enrichIdsWithNames } from "../_shared/names.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405);
  }

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const childId = segments[segments.length - 1];

  if (!childId || childId === "mark-confession-reminder-read") {
    return errorResponse("child id is required in the URL path", 400);
  }

  const { data, error } = await supabase.rpc("mark_confession_reminder_read", {
    p_child_id: childId,
  });

  if (error) {
    const status = error.code === "42501" ? 403 : 400;
    return errorResponse(error.message, status);
  }

  const enriched = await enrichIdsWithNames(supabase, {
    child_id: data.id,
    father_id: data.father_id,
  }) as Record<string, unknown>;

  return jsonResponse({
    success: true,
    child_id: data.id,
    child_name: data.name,
    father_id: data.father_id,
    father_name: enriched.father_name ?? null,
    reminder_is_read: data.reminder_is_read,
  });
});
