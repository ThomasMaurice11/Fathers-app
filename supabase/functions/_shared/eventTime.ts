/** Accepts HH:MM or HH:MM:SS; returns HH:MM:SS for Postgres `time`, or null to clear. */
export function parseOptionalEventTime(
  value: unknown
): { ok: true; time: string | null } | { ok: false; error: string } {
  if (value === undefined) {
    return { ok: true, time: null };
  }
  if (value === null || value === "") {
    return { ok: true, time: null };
  }
  if (typeof value !== "string") {
    return { ok: false, error: "event_time must be a string (HH:MM) or null" };
  }

  const trimmed = value.trim();
  if (!trimmed) return { ok: true, time: null };

  const match = /^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/.exec(trimmed);
  if (!match) {
    return { ok: false, error: "event_time must be a valid time (HH:MM)" };
  }

  const hours = match[1];
  const minutes = match[2];
  const seconds = match[3] ?? "00";
  return { ok: true, time: `${hours}:${minutes}:${seconds}` };
}
