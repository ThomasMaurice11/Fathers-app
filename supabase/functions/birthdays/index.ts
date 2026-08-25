// Routes (relative to /functions/v1/birthdays):
//   GET /today              -> today's birthdays
//   GET /?date=YYYY-MM-DD   -> birthdays for a selected date (month/day only, year ignored)

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";

function parsePath(req: Request) {
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const idx = segments.indexOf("birthdays");
  return segments.slice(idx + 1);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return errorResponse("Method not allowed", 405);

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const rest = parsePath(req);
  const url = new URL(req.url);

  const date =
    rest[0] === "today"
      ? new Date().toISOString().slice(0, 10)
      : url.searchParams.get("date") ?? new Date().toISOString().slice(0, 10);

  if (isNaN(Date.parse(date))) return errorResponse("date must be a valid date", 400);

  const { data, error } = await supabase.rpc("get_birthdays", { p_date: date });
  if (error) return errorResponse(error.message, 400);

  return jsonResponse({ data });
});
