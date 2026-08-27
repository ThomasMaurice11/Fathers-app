// Attach father_name / child_name whenever a payload exposes father_id / child_id.

import { getUserClient } from "./supabaseClient.ts";

type Client = ReturnType<typeof getUserClient>;
type Row = Record<string, unknown>;

export async function enrichIdsWithNames(
  supabase: Client,
  rows: Row | Row[] | null | undefined,
): Promise<Row | Row[] | null | undefined> {
  if (rows == null) return rows;

  const list = Array.isArray(rows) ? rows : [rows];
  if (list.length === 0) return rows;

  const fatherIds = [
    ...new Set(
      list
        .map((r) => r.father_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0),
    ),
  ];
  const childIds = [
    ...new Set(
      list
        .map((r) => r.child_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0),
    ),
  ];

  const fatherMap = new Map<string, string>();
  const childMap = new Map<string, string>();

  if (fatherIds.length > 0) {
    const { data } = await supabase
      .from("profiles")
      .select("id, full_name")
      .in("id", fatherIds);
    for (const p of data ?? []) {
      fatherMap.set(p.id, p.full_name);
    }
  }

  if (childIds.length > 0) {
    const { data } = await supabase
      .from("children")
      .select("id, name")
      .in("id", childIds);
    for (const c of data ?? []) {
      childMap.set(c.id, c.name);
    }
  }

  const enrich = (r: Row): Row => {
    const out: Row = { ...r };
    if (typeof r.father_id === "string") {
      out.father_name = fatherMap.get(r.father_id) ?? null;
    }
    if (typeof r.child_id === "string") {
      out.child_name = childMap.get(r.child_id) ?? null;
    }
    return out;
  };

  return Array.isArray(rows) ? list.map(enrich) : enrich(list[0]);
}
