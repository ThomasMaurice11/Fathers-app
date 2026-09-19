// Routes (relative to /functions/v1/events):
//   GET    /general/today       -> today's general events
//   GET    /general?date=...    -> general events for a given date (default today)
//   GET    /                    -> all my general events (optionally ?date=)
//   POST   /                    -> create a general event
//   PATCH  /:id                 -> update a general event
//   DELETE /:id                 -> delete a general event
//   PATCH  /:id/read            -> mark a general event as read

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";
import { enrichIdsWithNames } from "../_shared/names.ts";
import { parseOptionalEventTime } from "../_shared/eventTime.ts";

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
      .from("notifications")
      .select("*")
      .eq("type", "GENERAL")
      .eq("notification_date", new Date().toISOString().slice(0, 10))
      .order("event_time", { ascending: true, nullsFirst: false })
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
      .from("notifications")
      .select("*")
      .eq("type", "GENERAL")
      .eq("notification_date", date)
      .order("event_time", { ascending: true, nullsFirst: false })
      .order("created_at", { ascending: false });

    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
  }

  // ---------- /events/:id/read ----------
  if (rest[1] === "read") {
    if (req.method !== "PATCH") return errorResponse("Method not allowed", 405);

    const { data, error } = await supabase
      .from("notifications")
      .update({ is_read: true, status: "READ", read_at: new Date().toISOString() })
      .eq("id", rest[0])
      .eq("type", "GENERAL")
      .select()
      .maybeSingle();

    if (error) return errorResponse(error.message, 400);
    if (!data) return errorResponse("Event not found or not owned by you", 404);

    return jsonResponse({
      success: true,
      data: await enrichIdsWithNames(supabase, data),
    });
  }

  // ---------- /events/:id ----------
  if (rest.length === 1 && rest[0] !== "general") {
    const id = rest[0];

    if (req.method === "PATCH") {
      let body: {
        title?: string;
        message?: string | null;
        event_date?: string;
        notification_date?: string;
        event_time?: string | null;
        child_id?: string | null;
      };
      try {
        body = await req.json();
      } catch {
        return errorResponse("Invalid JSON body", 400);
      }

      const update: Record<string, unknown> = {};

      if (body.title !== undefined) {
        if (!body.title.trim()) return errorResponse("title cannot be blank", 400);
        update.title = body.title.trim();
      }
      if (body.message !== undefined) {
        update.message = body.message?.trim() ? body.message.trim() : null;
      }

      const dateValue = body.event_date ?? body.notification_date;
      if (dateValue !== undefined) {
        if (!dateValue || isNaN(Date.parse(dateValue))) {
          return errorResponse("event_date must be a valid date", 400);
        }
        update.notification_date = dateValue;
      }
      if (body.event_time !== undefined) {
        const parsed = parseOptionalEventTime(body.event_time);
        if (!parsed.ok) return errorResponse(parsed.error, 400);
        update.event_time = parsed.time;
      }
      if (body.child_id !== undefined) {
        update.child_id = body.child_id ?? null;
      }

      if (Object.keys(update).length === 0) {
        return errorResponse("No updatable fields supplied", 400);
      }

      const { data, error } = await supabase
        .from("notifications")
        .update(update)
        .eq("id", id)
        .eq("type", "GENERAL")
        .select()
        .maybeSingle();

      if (error) return errorResponse(error.message, 400);
      if (!data) return errorResponse("Event not found or not owned by you", 404);

      return jsonResponse({
        success: true,
        data: await enrichIdsWithNames(supabase, data),
      });
    }

    if (req.method === "DELETE") {
      const { data, error } = await supabase
        .from("notifications")
        .delete()
        .eq("id", id)
        .eq("type", "GENERAL")
        .select("id")
        .maybeSingle();

      if (error) return errorResponse(error.message, 400);
      if (!data) return errorResponse("Event not found or not owned by you", 404);

      return jsonResponse({ success: true, data: { id: data.id } });
    }

    return errorResponse("Method not allowed", 405);
  }

  // ---------- /events ----------
  if (rest.length === 0 && req.method === "GET") {
    const date = url.searchParams.get("date");
    let query = supabase.from("notifications").select("*").eq("type", "GENERAL");
    if (date) {
      if (isNaN(Date.parse(date))) return errorResponse("date must be a valid date", 400);
      query = query.eq("notification_date", date);
    }
    const { data, error } = await query.order("notification_date", { ascending: false });
    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
  }

  if (rest.length === 0 && req.method === "POST") {
    let body: {
      title?: string;
      message?: string;
      event_date?: string;
      event_time?: string | null;
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

    const parsedTime = parseOptionalEventTime(body.event_time);
    if (!parsedTime.ok) return errorResponse(parsedTime.error, 400);

    const { data, error } = await supabase
      .from("notifications")
      .insert({
        father_id: user.id,
        type: "GENERAL",
        title: body.title.trim(),
        message: body.message?.trim() ? body.message.trim() : null,
        notification_date: body.event_date,
        event_time: parsedTime.time,
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
