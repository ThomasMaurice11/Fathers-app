// Routes (relative to /functions/v1/notifications):
//   GET  /month?year=YYYY&month=M  -> general events for a given month (defaults to current)
//   POST /                         -> create a general event/notification

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";
import { enrichIdsWithNames } from "../_shared/names.ts";

function parsePath(req: Request) {
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const idx = segments.indexOf("notifications");
  return segments.slice(idx + 1);
}

function pad2(n: number) {
  return String(n).padStart(2, "0");
}

function monthRange(year: number, month: number) {
  const start = `${year}-${pad2(month)}-01`;
  const nextYear = month === 12 ? year + 1 : year;
  const nextMonth = month === 12 ? 1 : month + 1;
  const endExclusive = `${nextYear}-${pad2(nextMonth)}-01`;
  return { start, endExclusive };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const rest = parsePath(req);
  const url = new URL(req.url);

  // ---------- /notifications/month?year=&month= ----------
  if (rest[0] === "month") {
    if (req.method !== "GET") return errorResponse("Method not allowed", 405);

    const now = new Date();
    const yearParam = url.searchParams.get("year");
    const monthParam = url.searchParams.get("month");

    const year = yearParam != null ? Number(yearParam) : now.getUTCFullYear();
    const month = monthParam != null ? Number(monthParam) : now.getUTCMonth() + 1;

    if (!Number.isInteger(year) || year < 1) {
      return errorResponse("year must be a valid integer", 400);
    }
    if (!Number.isInteger(month) || month < 1 || month > 12) {
      return errorResponse("month must be an integer between 1 and 12", 400);
    }

    const { start, endExclusive } = monthRange(year, month);

    const { data, error } = await supabase
      .from("notifications")
      .select("*")
      .eq("type", "GENERAL")
      .gte("notification_date", start)
      .lt("notification_date", endExclusive)
      .order("notification_date", { ascending: true });

    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
  }

  // ---------- POST /notifications ----------
  if (rest.length === 0 && req.method === "POST") {
    let body: {
      title?: string;
      message?: string;
      notification_date?: string;
      child_id?: string | null;
    };
    try {
      body = await req.json();
    } catch {
      return errorResponse("Invalid JSON body", 400);
    }

    if (!body.title || !body.title.trim()) return errorResponse("title is required", 400);
    if (!body.notification_date || isNaN(Date.parse(body.notification_date))) {
      return errorResponse("notification_date must be a valid date", 400);
    }

    const { data, error } = await supabase
      .from("notifications")
      .insert({
        father_id: user.id,
        type: "GENERAL",
        title: body.title.trim(),
        message: body.message?.trim() ? body.message.trim() : null,
        notification_date: body.notification_date,
        child_id: body.child_id ?? null,
      })
      .select()
      .single();

    if (error) return errorResponse(error.message, 400);
    return jsonResponse({
      success: true,
      data: await enrichIdsWithNames(supabase, data),
    }, 201);
  }

  return errorResponse("Not found", 404);
});
