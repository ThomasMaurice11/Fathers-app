// Routes (relative to /functions/v1/events):
//   GET    /general/today       -> today's general events
//   GET    /general?date=...    -> general events for a given date (default today)
//   GET    /                    -> all my general events (optionally ?date=)
//   POST   /                    -> create a general event
//   PATCH  /:id/read            -> mark a general event as read

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";
import { enrichIdsWithNames } from "../_shared/names.ts";

function parsePath(req: Request) {
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const idx = segments.indexOf("events");
  return segments.slice(idx + 1);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const rest = parsePath(req);
  const url = new URL(req.url);

  // ---------- /events/general/today ----------
  if (rest[0] === "general" && rest[1] === "today") {
    if (req.method !== "GET") return errorResponse("Method not allowed", 405);

    const { data, error } = await supabase
      .from("events")
      .select("*")
      .eq("type", "GENERAL")
      .eq("event_date", new Date().toISOString().slice(0, 10))
      .order("created_at", { ascending: false });

    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
  }

  // ---------- /events/general?date=YYYY-MM-DD ----------
  if (rest[0] === "general") {
    if (req.method !== "GET") return errorResponse("Method not allowed", 405);

    const date = url.searchParams.get("date") ?? new Date().toISOString().slice(0, 10);
    if (isNaN(Date.parse(date))) return errorResponse("date must be a valid date", 400);

    const { data, error } = await supabase
      .from("events")
      .select("*")
      .eq("type", "GENERAL")
      .eq("event_date", date)
      .order("created_at", { ascending: false });

    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
  }

  // ---------- /events/:id/read ----------
  if (rest[1] === "read") {
    if (req.method !== "PATCH") return errorResponse("Method not allowed", 405);

    const { data, error } = await supabase
      .from("events")
      .update({ is_read: true, status: "READ", read_at: new Date().toISOString() })
      .eq("id", rest[0])
      .select()
      .maybeSingle();

    if (error) return errorResponse(error.message, 400);
    if (!data) return errorResponse("Event not found or not owned by you", 404);

    return jsonResponse({
      success: true,
      data: await enrichIdsWithNames(supabase, data),
    });
  }

  // ---------- /events ----------
  if (req.method === "GET") {
    const date = url.searchParams.get("date");
    let query = supabase.from("events").select("*").eq("type", "GENERAL");
    if (date) {
      if (isNaN(Date.parse(date))) return errorResponse("date must be a valid date", 400);
      query = query.eq("event_date", date);
    }
    const { data, error } = await query.order("event_date", { ascending: false });
    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
  }

  if (req.method === "POST") {
    let body: {
      title?: string;
      message?: string;
      event_date?: string;
      child_id?: string | null;
    };
    try {
      body = await req.json();
    } catch {
      return errorResponse("Invalid JSON body", 400);
    }

    if (!body.title || !body.title.trim()) return errorResponse("title is required", 400);
    if (!body.event_date || isNaN(Date.parse(body.event_date))) {
      return errorResponse("event_date must be a valid date", 400);
    }

    const { data, error } = await supabase
      .from("events")
      .insert({
        father_id: user.id,
        type: "GENERAL",
        title: body.title,
        message: body.message ?? null,
        event_date: body.event_date,
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

  return errorResponse("Method not allowed", 405);
});
