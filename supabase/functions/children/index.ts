// All child + confession-history data access lives here so the
// frontend never calls supabase-js .from(...) directly.
//
// Routes (relative to /functions/v1/children):
//   GET    /                          -> list my children
//   GET    /:id                       -> single child detail (+ confession history)
//   POST   /                          -> create child
//   PATCH  /:id                       -> update child
//   DELETE /:id                       -> delete child
//   GET    /:id/confessions           -> confession history for a child
//   POST   /:id/confessions           -> create a confession (atomic reminder reset)
//   GET    /:id/operations            -> operations for a child
//   POST   /:id/operations            -> create an operation
//   PATCH  /:id/operations/:operationId -> update an operation
//   DELETE /:id/operations/:operationId -> delete an operation
//   GET    /:id/events                -> notifications/events for a child

import { corsHeaders, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthenticatedUser } from "../_shared/supabaseClient.ts";
import { enrichIdsWithNames } from "../_shared/names.ts";

function childNameExistsMessage() {
  return "This child already exists";
}

/** Egyptian mobile 010/011/012/015. Accepts local, +20, or 0020. Returns +20… or null if blank/invalid. */
function normalizeEgyptianPhone(input: string | null | undefined): string | null {
  if (input == null) return null;
  const raw = input.trim();
  if (!raw) return null;

  let digits = raw.replace(/[^\d+]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith("0") && !digits.startsWith("20")) {
    digits = `20${digits.slice(1)}`;
  }

  if (!/^201[0125]\d{8}$/.test(digits)) return null;
  return `+${digits}`;
}

function parseOptionalEgyptianPhone(input: string | null | undefined): { ok: true; value: string | null } | { ok: false } {
  if (input == null || !String(input).trim()) return { ok: true, value: null };
  const normalized = normalizeEgyptianPhone(input);
  if (!normalized) return { ok: false };
  return { ok: true, value: normalized };
}

function mapChildWriteError(error: { code?: string; message: string }) {
  if (error.code === "23505") return errorResponse(childNameExistsMessage(), 409);
  if (error.code === "23503") return errorResponse("stage_id does not exist", 400);
  return errorResponse(error.message, 400);
}

function parsePath(req: Request) {
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  // segments look like: ["functions", "v1", "children", ":id?", "confessions"|"operations"?]
  const idx = segments.indexOf("children");
  return segments.slice(idx + 1); // e.g. [] | [id] | [id, "confessions"] | [id, "operations", operationId]
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const { supabase, user } = await getAuthenticatedUser(req);
  if (!user) return errorResponse("Unauthorized", 401);

  const rest = parsePath(req);
  const [id, subresource, subresourceId] = rest;

  // ---------- /children/:id/events ----------
  if (id && subresource === "events") {
    if (req.method === "GET" && !subresourceId) {
      const { data, error } = await supabase
        .from("notifications")
        .select("*")
        .eq("child_id", id)
        .order("notification_date", { ascending: false });

      if (error) return errorResponse(error.message, 400);
      return jsonResponse({ data: await enrichIdsWithNames(supabase, data) });
    }

    return errorResponse("Method not allowed", 405);
  }

  // ---------- /children/:id/operations[/:operationId] ----------
  if (id && subresource === "operations") {
    if (req.method === "GET" && !subresourceId) {
      const { data, error } = await supabase
        .from("operations")
        .select("id, type, note, operation_date, created_at, updated_at")
        .eq("child_id", id)
        .order("operation_date", { ascending: false });

      if (error) return errorResponse(error.message, 400);
      return jsonResponse({ data });
    }

    if (req.method === "POST" && !subresourceId) {
      let body: { type?: string; note?: string; operation_date?: string };
      try {
        body = await req.json();
      } catch {
        return errorResponse("Invalid JSON body", 400);
      }
      if (!body.type || !body.type.trim()) {
        return errorResponse("type is required", 400);
      }
      if (!body.operation_date || isNaN(Date.parse(body.operation_date))) {
        return errorResponse("operation_date must be a valid date", 400);
      }

      const { data, error } = await supabase
        .from("operations")
        .insert({
          father_id: user.id,
          child_id: id,
          type: body.type,
          note: body.note ?? null,
          operation_date: body.operation_date,
        })
        .select()
        .single();

      if (error) {
        const status = error.code === "42501" ? 403 : 400;
        return errorResponse(error.message, status);
      }

      return jsonResponse({
        success: true,
        data: await enrichIdsWithNames(supabase, data),
      }, 201);
    }

    if (subresourceId && req.method === "PATCH") {
      let body: { type?: string; note?: string; operation_date?: string };
      try {
        body = await req.json();
      } catch {
        return errorResponse("Invalid JSON body", 400);
      }

      const update: Record<string, unknown> = {};
      if (body.type !== undefined) {
        if (!body.type.trim()) return errorResponse("type cannot be blank", 400);
        update.type = body.type;
      }
      if (body.note !== undefined) update.note = body.note;
      if (body.operation_date !== undefined) {
        if (isNaN(Date.parse(body.operation_date))) {
          return errorResponse("operation_date must be a valid date", 400);
        }
        update.operation_date = body.operation_date;
      }

      if (Object.keys(update).length === 0) {
        return errorResponse("No updatable fields supplied", 400);
      }

      const { data, error } = await supabase
        .from("operations")
        .update(update)
        .eq("id", subresourceId)
        .eq("child_id", id)
        .select()
        .maybeSingle();

      if (error) return errorResponse(error.message, 400);
      if (!data) return errorResponse("Operation not found or not owned by you", 404);

      return jsonResponse({
        success: true,
        data: await enrichIdsWithNames(supabase, data),
      });
    }

    if (subresourceId && req.method === "DELETE") {
      const { data, error } = await supabase
        .from("operations")
        .delete()
        .eq("id", subresourceId)
        .eq("child_id", id)
        .select("id")
        .maybeSingle();

      if (error) return errorResponse(error.message, 400);
      if (!data) return errorResponse("Operation not found or not owned by you", 404);

      return jsonResponse({ success: true, operation_id: subresourceId });
    }

    return errorResponse("Method not allowed", 405);
  }

  // ---------- /children/:id/confessions ----------
  if (id && subresource === "confessions") {
    if (req.method === "GET") {
      const { data, error } = await supabase
        .from("confession_history")
        .select("id, confession_at, notes, created_at")
        .eq("child_id", id)
        .order("confession_at", { ascending: false });

      if (error) return errorResponse(error.message, 400);
      return jsonResponse({ data });
    }

    if (req.method === "POST") {
      let body: { confession_at?: string; notes?: string };
      try {
        body = await req.json();
      } catch {
        return errorResponse("Invalid JSON body", 400);
      }
      if (!body.confession_at || isNaN(Date.parse(body.confession_at))) {
        return errorResponse("confession_at must be a valid timestamp", 400);
      }

      const { data, error } = await supabase.rpc("create_confession", {
        p_child_id: id,
        p_confession_at: body.confession_at,
        p_notes: body.notes ?? null,
      });

      if (error) {
        const status = error.code === "42501" ? 403 : 400;
        return errorResponse(error.message, status);
      }

      const row = Array.isArray(data) ? data[0] : data;
      return jsonResponse({
        success: true,
        child_id: row.child_id,
        child_name: row.child_name,
        father_id: row.father_id,
        father_name: row.father_name,
        confession_id: row.confession_id,
        confession_at: row.confession_at,
        reminder_is_read: row.reminder_is_read,
        reminder_snoozed_until: row.reminder_snoozed_until,
      });
    }

    return errorResponse("Method not allowed", 405);
  }

  // ---------- /children/:id ----------
  if (id) {
    if (req.method === "GET") {
      const { data, error } = await supabase.rpc("get_child_detail", { p_child_id: id });
      if (error) return errorResponse(error.message, 400);
      if (!data) return errorResponse("Child not found", 404);
      return jsonResponse({ data });
    }

    if (req.method === "PATCH") {
      let body: {
        name?: string;
        birthday?: string | null;
        marriage_contract?: string | null;
        phone_number?: string | null;
        stage_id?: number;
      };
      try {
        body = await req.json();
      } catch {
        return errorResponse("Invalid JSON body", 400);
      }

      const update: Record<string, unknown> = {};
      if (body.name !== undefined) {
        if (!body.name.trim()) return errorResponse("name cannot be blank", 400);
        update.name = body.name.trim();
      }
      if (body.birthday !== undefined) {
        if (body.birthday !== null && isNaN(Date.parse(body.birthday))) {
          return errorResponse("birthday must be a valid date", 400);
        }
        update.birthday = body.birthday;
      }
      if (body.marriage_contract !== undefined) {
        if (body.marriage_contract !== null && isNaN(Date.parse(body.marriage_contract))) {
          return errorResponse("marriage_contract must be a valid date", 400);
        }
        update.marriage_contract = body.marriage_contract;
      }
      if (body.phone_number !== undefined) {
        const phone = parseOptionalEgyptianPhone(body.phone_number);
        if (!phone.ok) {
          return errorResponse(
            "phone_number must be a valid Egyptian mobile (010, 011, 012, or 015)",
            400,
          );
        }
        update.phone_number = phone.value;
      }
      if (body.stage_id !== undefined) update.stage_id = body.stage_id;

      if (Object.keys(update).length === 0) {
        return errorResponse("No updatable fields supplied", 400);
      }

      if (update.name !== undefined) {
        const { data: existing } = await supabase
          .from("children")
          .select("id")
          .eq("father_id", user.id)
          .ilike("name", update.name as string)
          .neq("id", id)
          .maybeSingle();

        if (existing) {
          return errorResponse(childNameExistsMessage(), 409);
        }
      }

      const { data, error } = await supabase
        .from("children")
        .update(update)
        .eq("id", id)
        .select()
        .maybeSingle();

      if (error) {
        return mapChildWriteError(error);
      }
      if (!data) return errorResponse("Child not found or not owned by you", 404);

      return jsonResponse({
        success: true,
        data: await enrichIdsWithNames(supabase, data),
      });
    }

    if (req.method === "DELETE") {
      const { data, error } = await supabase
        .from("children")
        .delete()
        .eq("id", id)
        .select("id, name, father_id")
        .maybeSingle();

      if (error) return errorResponse(error.message, 400);
      if (!data) return errorResponse("Child not found or not owned by you", 404);

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
      });
    }

    return errorResponse("Method not allowed", 405);
  }

  // ---------- /children ----------
  if (req.method === "GET") {
    const { data, error } = await supabase.rpc("get_children");
    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ data });
  }

  if (req.method === "POST") {
    let body: {
      name?: string;
      birthday?: string;
      marriage_contract?: string;
      phone_number?: string | null;
      stage_id?: number;
    };
    try {
      body = await req.json();
    } catch {
      return errorResponse("Invalid JSON body", 400);
    }

    if (!body.name || !body.name.trim()) {
      return errorResponse("name is required", 400);
    }
    if (body.stage_id === undefined || body.stage_id === null) {
      return errorResponse("stage_id is required", 400);
    }
    if (body.birthday && isNaN(Date.parse(body.birthday))) {
      return errorResponse("birthday must be a valid date", 400);
    }
    if (body.marriage_contract && isNaN(Date.parse(body.marriage_contract))) {
      return errorResponse("marriage_contract must be a valid date", 400);
    }

    const phone = parseOptionalEgyptianPhone(body.phone_number);
    if (!phone.ok) {
      return errorResponse(
        "phone_number must be a valid Egyptian mobile (010, 011, 012, or 015)",
        400,
      );
    }

    const trimmedName = body.name.trim();

    const { data: existing } = await supabase
      .from("children")
      .select("id")
      .eq("father_id", user.id)
      .ilike("name", trimmedName)
      .maybeSingle();

    if (existing) {
      return errorResponse(childNameExistsMessage(), 409);
    }

    // father_id is ALWAYS derived server-side from the authenticated
    // user — any father_id in the request body is ignored.
    const { data, error } = await supabase
      .from("children")
      .insert({
        father_id: user.id,
        name: trimmedName,
        birthday: body.birthday ?? null,
        marriage_contract: body.marriage_contract ?? null,
        phone_number: phone.value,
        stage_id: body.stage_id,
      })
      .select()
      .single();

    if (error) {
      return mapChildWriteError(error);
    }

    return jsonResponse({
      success: true,
      data: await enrichIdsWithNames(supabase, data),
    }, 201);
  }

  return errorResponse("Method not allowed", 405);
});
