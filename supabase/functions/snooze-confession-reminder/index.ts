// POST /functions/v1/snooze-confession-reminder/:childId
// Body: { "snoozed_until": "YYYY-MM-DD" }

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

  if (!childId || childId === "snooze-confession-reminder") {
    return errorResponse("child id is required in the URL path", 400);
  }

  let body: { snoozed_until?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400);
  }

  if (!body.snoozed_until || isNaN(Date.parse(body.snoozed_until))) {
    return errorResponse("snoozed_until must be a valid date (YYYY-MM-DD)", 400);
  }

  const { data, error } = await supabase.rpc("snooze_confession_reminder", {
    p_child_id: childId,
    p_snoozed_until: body.snoozed_until,
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
    reminder_snoozed_until: data.reminder_snoozed_until,
  });
});
