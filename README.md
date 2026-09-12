# Church Fathers App — Supabase Backend (code-first)

This folder is a complete, code-first Supabase backend matching the spec:
5 tables, RLS policies, dynamically-calculated confession reminders, and
5 Edge Functions for the atomic/aggregate operations.

```
church-fathers-app/
├── supabase/
│   ├── config.toml
│   ├── migrations/          11 numbered SQL files, run in order
│   └── functions/
│       ├── _shared/                        cors.ts, supabaseClient.ts
│       ├── login/
│       ├── register/                       ADMIN-only user provisioning
│       ├── forgot-password/
│       ├── set-new-password/
│       ├── change-password/
│       ├── children/                       full CRUD + nested confessions
│       ├── confession-reminders/           GET (dynamically calculated)
│       ├── mark-confession-reminder-read/
│       ├── snooze-confession-reminder/
│       ├── events/                         general events CRUD
│       ├── notifications/                  month calendar + create notification
│       ├── birthdays/
│       ├── stages/                         read-only reference data
│       └── dashboard/
├── scripts/setup.sh
├── .env.example
└── README.md
```

**Every** data API is an Edge Function. The frontend never calls
`supabase.from(...)` directly — Auth is via Edge Functions (`/login`,
`/register`, password flows) or `supabase.auth.*` where needed for the
recovery session after a reset email, and `supabase.functions.invoke(...)`
for everything else. Most Edge Functions create a Supabase client using
the caller's own JWT (see `_shared/supabaseClient.ts`), so RLS remains
the underlying security boundary. `/register` additionally uses the
service role **after** verifying the caller is an ADMIN, solely to call
`auth.admin.createUser`.

Public self-signup is **disabled** (`enable_signup = false`). Only an
admin can create users via `POST /register`.

---

## 0. Prerequisites

You only need **Node.js 18+** installed. The Supabase CLI is run through
`npx`, so nothing needs a global install.

```bash
node -v
```

---

## 1. Create the Supabase project

1. Go to https://supabase.com/dashboard → **New project**.
2. Note the **Project Ref** (in the project URL / Settings → General).
3. Settings → API → copy the **Project URL** and **anon/public key**.

---

## 2. Bootstrap this repo locally

From inside `church-fathers-app/`:

```bash
bash scripts/setup.sh
```

This checks Node/npx, verifies the Supabase CLI runs, and copies
`.env.example` → `.env` for you to fill in.

---

## 3. Commands you need to know (in order)

```bash
# 1. Log in once (opens a browser for auth)
npx supabase login

# 2. Link this local folder to your remote project
npx supabase link --project-ref <your-project-ref>

# 3. Push all local migrations (creates tables, enums, RLS, functions, seed data)
npx supabase db push

# 4. Deploy all Edge Functions at once
npx supabase functions deploy

#    ...or deploy just one while iterating:
npx supabase functions deploy create-confession

# 5. Set any secrets your functions need at runtime
#    (SUPABASE_URL / SUPABASE_ANON_KEY are injected automatically by
#    the platform — you generally don't need to set these yourself)
npx supabase secrets list

# 6. Generate TypeScript types for the frontend from your live schema
npx supabase gen types typescript --linked > src/types/database.types.ts
```

### Local development loop (optional but recommended)

Run a full local Supabase stack in Docker so you're not touching
production while building:

```bash
npx supabase start          # spins up local Postgres, Auth, Studio, API
npx supabase db reset       # (re)applies all migrations + seed data locally
npx supabase functions serve   # serves edge functions locally with hot reload
npx supabase stop           # shut it down
```

`supabase db reset` is your main iteration command: edit a migration
file (or add a new numbered one), run `db reset`, it replays everything
from scratch against your local DB — cheap and repeatable. Only run
`supabase db push` against the remote project once you're happy.

### Adding a new migration later

Never edit an already-pushed migration file. Create a new one:

```bash
npx supabase migration new add_something_new
# edit the generated file under supabase/migrations/
npx supabase db push
```

---

## 4. Full API reference (all Edge Functions)

Base URL: `https://<project-ref>.supabase.co/functions/v1`
Every call needs both headers below (user token, not the service role key):

```
Authorization: Bearer <user-access-token>
apikey: <anon-key>
```

Get a test access token from Studio → Authentication, or by signing up
a test user from your frontend and logging the session.

| Method | Path | Purpose |
|---|---|---|
| POST | `/login` | Get an access token (email + password → access_token). No Bearer needed. |
| POST | `/register` | **ADMIN only** — create a user (`email`, `password`, `full_name`, `role`: `FATHER` \| `ADMIN`) |
| POST | `/forgot-password` | Send password-reset email (`{ "email" }`). No Bearer needed. |
| POST | `/set-new-password` | Set password with recovery/session JWT (`{ "password" }`) |
| POST | `/change-password` | Logged-in change (`{ "current_password", "new_password" }`) |
| GET | `/children` | List my children (age, stage, confession status included) |
| GET | `/children/:id` | Child detail + full confession history |
| POST | `/children` | Create a child |
| PATCH | `/children/:id` | Update a child |
| DELETE | `/children/:id` | Delete a child |
| GET | `/children/:id/confessions` | Confession history for a child |
| POST | `/children/:id/confessions` | Record a confession (atomic: inserts history + resets reminder) |
| GET | `/confession-reminders` | Active overdue reminders (`?unread_only=true` supported) |
| POST | `/mark-confession-reminder-read/:childId` | Mark a reminder as read |
| POST | `/snooze-confession-reminder/:childId` | Snooze a reminder (`{ "snoozed_until": "YYYY-MM-DD" }`) |
| GET | `/events` | My general events (`?date=YYYY-MM-DD` optional) |
| GET | `/events/general/today` | Today's general events |
| GET | `/events/general?date=YYYY-MM-DD` | General events for a date |
| POST | `/events` | Create a general event |
| PATCH | `/events/:id/read` | Mark a general event as read |
| GET | `/notifications/month` | Month events (`?year=&month=`, defaults to current UTC) |
| POST | `/notifications` | Create notification (`title`, `notification_date`, optional `message`/`child_id`) |
| GET | `/birthdays/today` | Today's birthdays |
| GET | `/birthdays?date=YYYY-MM-DD` | Birthdays for a date (month/day only) |
| GET | `/stages` | List the 19 predefined stages (read-only) |
| GET | `/dashboard` | Combined dashboard payload (dates in Africa/Cairo; general events = today through today+6) |

### Examples

```bash
# get an access token (replaces the manual auth/v1/token curl)
curl -X POST "$BASE/login" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"abonakero@gmail.com","password":"YourPassword123!"}'

# admin creates a father (Bearer must be an ADMIN user's access_token)
curl -X POST "$BASE/register" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"new.father@example.com","password":"TempPass123!","full_name":"Abouna Michael","role":"FATHER"}'

# request password reset email
curl -X POST "$BASE/forgot-password" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"abonakero@gmail.com"}'

# set new password (after recovery link; use the recovery access_token)
curl -X POST "$BASE/set-new-password" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"password":"NewPassword123!"}'

# change password while logged in
curl -X POST "$BASE/change-password" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"current_password":"YourPassword123!","new_password":"NewPassword123!"}'

# list children
curl -X GET "$BASE/children" -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY"

# create a child
curl -X POST "$BASE/children" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"first_name":"Michael","last_name":"Maurice","birthday":"2010-08-20","stage_id":9}'

# record a confession (atomic reminder reset happens server-side)
curl -X POST "$BASE/children/<child-uuid>/confessions" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"confession_at":"2026-08-23T10:00:00Z","notes":"ok"}'

# active confession reminders
curl -X GET "$BASE/confession-reminders" -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY"

# mark a reminder as read
curl -X POST "$BASE/mark-confession-reminder-read/<child-uuid>" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY"

# snooze a reminder
curl -X POST "$BASE/snooze-confession-reminder/<child-uuid>" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"snoozed_until":"2026-08-30"}'

# create a general event
curl -X POST "$BASE/events" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"title":"Church Meeting","message":"Meeting at 7 PM","event_date":"2026-08-20"}'

# month notifications calendar
curl -X GET "$BASE/notifications/month?year=2026&month=9" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY"

# create a notification (uses public.notifications)
curl -X POST "$BASE/notifications" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"title":"Church Meeting","message":"Meeting at 7 PM","notification_date":"2026-08-20"}'

# today's birthdays
curl -X GET "$BASE/birthdays/today" -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY"

# dashboard
curl -X GET "$BASE/dashboard" -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY"
```

## 5. Calling these from the React frontend

Use `supabase.functions.invoke(...)` — never `.from(...)`:

```ts
// list children
const { data, error } = await supabase.functions.invoke("children");

// create a child
await supabase.functions.invoke("children", {
  method: "POST",
  body: { first_name: "Michael", last_name: "Maurice", birthday: "2010-08-20", stage_id: 9 },
});

// record a confession — note the path segment after the function name
await supabase.functions.invoke(`children/${childId}/confessions`, {
  method: "POST",
  body: { confession_at: new Date().toISOString(), notes: "" },
});

// dashboard
const { data: dashboard } = await supabase.functions.invoke("dashboard");
```

`supabase.functions.invoke` automatically attaches the current user's
JWT, so you don't pass `Authorization` manually in the frontend code —
only in the raw `curl` examples above.

---

## 6. Design notes / how this maps to the spec

- **Every API is an Edge Function**, per your instruction — `children`,
  `events`, `birthdays`, and `stages` route GET/POST/PATCH/DELETE
  internally by parsing the request path, so one function folder covers
  a whole resource (e.g. `children` handles `/children`, `/children/:id`,
  and `/children/:id/confessions`).
- **Confession reminders are never stored.** `get_confession_reminders()`
  computes everything live from `children` + `confession_history`,
  applying the 27-day rule, the snooze date, and the read flag exactly
  as specified.
- **`create_confession()`** is one Postgres function = one transaction:
  insert the history row, then reset `reminder_is_read`/
  `reminder_snoozed_until` on `children`. Called from
  `POST /children/:id/confessions` so the whole operation is atomic and
  ownership is double-checked before anything is written.
- **RLS is still the real security boundary**, even though the frontend
  never touches tables directly. Every table policy filters on
  `father_id = auth.uid()` (or `id = auth.uid()` for `profiles`), so even
  if an Edge Function had a routing bug, Postgres itself refuses
  cross-father access. `stages` is readable by any authenticated user
  and has no write policies at all — writes are impossible by
  construction, from the client or from any function.
- **`SUPABASE_SERVICE_ROLE_KEY` is used only in `/register`**, after
  `requireAdmin` confirms `profiles.role = ADMIN`, to call
  `auth.admin.createUser`. All other Edge Functions use the caller's JWT
  (see `_shared/supabaseClient.ts`).
- **Admin bootstrap:** create the first user in Studio (or temporarily
  enable signup), then promote them in SQL:
  `update public.profiles set role = 'ADMIN' where email = 'you@example.com';`
- **Password reset emails:** hosted projects use Supabase’s built-in
  Auth mailer for light testing. For production, configure Custom SMTP
  under Project Settings → Authentication. Local `supabase start` catches
  mail in Inbucket instead of a real inbox.
