# DESIGN.md — "Lock in" (working name), personal habit and goal app for iOS

Audience: the planning model and the coding agents. Nobody is available to answer questions, so every rule below is meant to be built or tested as written. Items marked **[OPEN]** carry a recommended answer: build the recommendation. Items marked **[VERIFY]** are unconfirmed platform facts: build the stated approach, then check it on the device and report the result. **[needs account check]** marks a feature that may not be available when the app is signed with a free Apple ID.

Conventions used throughout:
- Weekdays are ISO numbers: 1 = Monday … 7 = Sunday.
- A time of day is `Int` minutes after midnight (07:30 = 450).
- A calendar day is `LocalDay`, stored as the string `"YYYY-MM-DD"` in the device time zone (Europe/London).
- A week runs from Monday 00:00 to Sunday 23:59 local time.
- **Day boundary:** a mark made between 00:00 and 03:59 is saved to the previous day by default. The mark sheet shows the date and lets the user change it.
- "Glass" means Apple's native Liquid Glass and nothing else (see §8.7).

---

## 1. Product summary

Lock in is a personal iOS app for one user: a first-year mechanical engineering student in Manchester. It is sideloaded on his iPhone (iOS 27) using a free Apple ID. It has three jobs:

1. **Habits.** Track daily and weekly habits with D / B / M marks (done, bad-day version, missed) and timed reminders.
2. **Goal creator.** Turn a big goal into a working system using his method: first principles, one system per principle, a sustaining system, and a graph of objectives with deadlines. Claude chat does the reasoning, and the app imports the result as JSON.
3. **Calendar.** A built-in calendar paired two-way with Apple Calendar, so goal blocks land in real free time around his uni timetable.

"Working" day to day means a morning summary, up to four timed nudges, an evening tick-off, and a Monday 19:00 check-in that fills itself in: never more than six notifications a day.

---

## 2. Scope

### 2.1 MVP features and acceptance criteria (checked on the phone)

| ID | Feature | Acceptance criteria |
|---|---|---|
| F1 | Habits: create, edit and archive. Kinds `check` and `count`. Frequencies `daily`, `weekdays`, `perWeek`. | 1. A habit set to Mon/Wed/Fri appears in Today only on those days. 2. A "5 per week" habit appears every day until 5 D/B marks are logged that week, then stops appearing until the next Monday. 3. Archiving a habit hides it but keeps its past marks in the Week tab history. |
| F2 | D / B / M marking | 1. Tapping a habit row opens the mark sheet. Tapping D closes the sheet, and the row shows a blue dot within 0.3 s. 2. For a count habit (target 4, bad-day target 3): stepping to 3 shows the mark as B; stepping to 4 shows D. 3. A mark made at 01:30 on Tuesday is saved to Monday. |
| F3 | Weekly scores, set points, streaks, bad-day flag | 1. A habit with set point 5 and 5 D/B marks counts as on target. 2. A habit with 3 done marks, 2 of them B, is flagged in the Week tab. 3. A goal streak goes up by 1 only after a week in which every habit of that goal hit its set point. |
| F4 | Reminders | 1. A habit with reminder time 07:30 fires a notification at 07:30 with the app closed. 2. On a day with 6 timed habits, only the 4 highest-priority ones notify. 3. Marking a habit D before its reminder time stops that day's reminder from firing. 4. Settings → Diagnostics never shows more than 61 pending notifications (60 regular + the re-sign warning). 5. Tapping a habit notification opens the mark sheet for that habit and day. |
| F5 | Goals dashboard, Today accessory, Monday check-in banner | 1. On launch the app opens on the Goals tab. 2. The Today accessory shows the next timed item and how many habits are left today. 3. On Mondays, the check-in banner shows until the check-in is finished, then disappears. |
| F6 | Goal intake and "Send to Claude" | 1. New goal runs 4 question rounds, and every question has a pre-filled default. 2. "Send to Claude" copies a prompt to the clipboard that contains every answer and the next 14 days of busy times, with no event titles. 3. The Claude app opens, or a "Copied. Open Claude and paste." message appears. |
| F7 | Plan import | 1. Pasting valid plan JSON shows the Import review with counts of principles, systems, habits and blocks. 2. Invalid JSON shows the failing field path, for example `habits[2].frequency.weekdays: 8 is not 1–7`, and creates nothing. 3. Opening a `.json` file from the Files app opens the Import review. 4. Tapping "Add to app" creates the habits, schedules their reminders and writes blocks to the Goals calendar. |
| F8 | Goal detail: map, outline, dependencies, back-scheduling | 1. Map shows goal → principles → systems → milestones top to bottom, with the sustaining system dashed at the bottom. 2. Choosing a dependency that would create a loop is disabled and shows the reason "Would create a loop". 3. Changing the goal deadline recalculates every milestone date that hasn't been overridden. |
| F9 | Calendar tab and Apple Calendar pairing | 1. The Week view shows uni timetable events from the subscribed calendar. 2. A goal block created in the app appears in Apple Calendar's "Goals" calendar within 5 s. 3. Moving that event in Apple Calendar moves the block in the app the next time the app opens. 4. A new Apple Calendar event overlapping a block marks it "Clash" and offers a new slot; nothing moves until "Move" is tapped. |
| F10 | Week check-in | 1. Opening the Week tab on Monday shows last week's marks already filled in. 2. "Finish" saves the review, writes a backup file and removes the Monday banner. 3. "Send to Claude" copies a check-in prompt containing the scorecard. 4. Importing the JSON that comes back updates the existing goal and does not create a second one. |
| F11 | Backup and restore | 1. After "Finish", a file `lockin-backup-YYYY-MM-DD.json` appears in the chosen folder. 2. Restoring from that file on a fresh install brings back every goal, habit and mark. |
| F12 | Re-sign warning | 1. When the signing profile expires within 48 h, a banner shows on the Goals tab and one notification fires. 2. Settings shows the expiry date and time. |
| F13 | Onboarding and permissions | 1. First launch asks for notifications, then calendar, each after an explanation screen. 2. If either is denied, the app still works and shows the denied state described in §7. |
| F14 | Settings | Every value in `AppSettings` (§3) can be edited, and each change reschedules notifications within 1 s. |
| F15 | Design system and Liquid Glass | 1. Dragging a finger across the tab bar shows the system lens. 2. Goal tiles scrolling under the tab bar show refracted light in it, not grey frost. |
| F16 | Cloud build | A push to `main` produces an unsigned `LockIn.ipa` artifact in GitHub Actions, and Sideloadly installs it. |

### 2.2 Later (not MVP)

| Feature | Why later |
|---|---|
| Month view | Day and Week cover planning. |
| Home Screen widgets | Need App Groups. [needs account check] |
| Siri / App Intents ("mark walk done") | [needs account check] |
| Snooze action on notifications | User chose notifications with no buttons. |
| Share-sheet import from Claude | Needs a share extension and App Groups. [needs account check] |
| iCloud sync | [needs account check]. The JSON backup covers loss. |
| In-app Claude API | User chose the chat handoff to avoid API cost. |
| Editable node map | Outline editing is cheaper and works by finger. |
| Light mode | Dark only by decision. |
| Background refresh of reminders | See §9.1. MVP refreshes whenever the app opens. |

---

## 3. Data model

Two layers:
- **CoreKit** (pure Swift, compiles on Linux) defines value-type structs with the names below. Relationships are UUID fields.
- **Persistence** (SwiftData, iOS only) defines `@Model` classes named `<Entity>Record` with real relationships, and maps them to and from the CoreKit structs.

Only `CalendarBlock` syncs with Apple Calendar. Every other entity lives on the device only.

All entities have `id: UUID` (primary key). Plan-imported entities also have `planKey: String?`, the `key` from the plan JSON, which is used to match entities on re-import.

### 3.1 Goal
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| planKey | String? | `goal.key` from JSON |
| title | String | "10% body fat" |
| outcome | String | One sentence describing what success looks like |
| deadline | LocalDay | |
| bufferDays | Int | Default 7 |
| status | enum `active, paused, achieved, dropped` | |
| resultName | String | "Weigh-in average" |
| resultUnit | String | "kg" |
| resultStart | Double | |
| resultTarget | Double | |
| resultDirection | enum `down, up` | |
| bottleneckHabitID | UUID? | Set at check-in |
| sortIndex | Int | Dashboard order |
| createdAt | Date | |
| importedPlanJSON | String? | Raw text of the last import, kept for debugging |

Relationships: has many FirstPrinciple, GoalSystem, Objective and WeekReview (all cascade on delete). Apple Calendar sync: no.

### 3.2 FirstPrinciple
id, planKey, goalID (UUID), title (String), why (String), sortIndex (Int). Has many GoalSystem (nullify on delete). Sync: no.

### 3.3 GoalSystem
| Field | Type | Notes |
|---|---|---|
| id, planKey | | |
| goalID | UUID | |
| firstPrincipleID | UUID? | nil when kind = sustaining |
| kind | enum `principle, sustaining` | Exactly one sustaining system per goal |
| title | String | |
| location | String? | "Library", "Gym" |
| sortIndex | Int | |

Has many Habit (nullify: deleting a system leaves its habits standalone), BlockRule (cascade) and PlanReminder (cascade). Many-to-many with Objective. Sync: no.

### 3.4 Objective (milestone, a DAG node)
| Field | Type | Notes |
|---|---|---|
| id, planKey | | |
| goalID | UUID | |
| title | String | "82.0 kg" |
| deadline | LocalDay? | Calculated by back-scheduling (§4.4) unless overridden |
| deadlineOverridden | Bool | |
| estimatedDays | Int | ≥ 1 |
| status | enum `notStarted, inProgress, done` | |
| dependsOnIDs | [UUID] | Other Objectives of the same goal. Must stay acyclic. |
| systemIDs | [UUID] | Systems that drive this milestone |
| sortIndex | Int | |

Has many Step (cascade). Sync: no.

### 3.5 Step
id, planKey, objectiveID, title (String), deadline (LocalDay?, defaults to the objective's deadline), estimatedMinutes (Int), done (Bool), sortIndex (Int). Sync: no.

### 3.6 Habit
| Field | Type | Notes |
|---|---|---|
| id, planKey | | |
| systemID | UUID? | nil = standalone habit |
| goalID | UUID? | Copied from the system; nil if standalone |
| title | String | "Incline walk" |
| badDayTitle | String | "20 min walk" (required) |
| kind | enum `check, count` | |
| target | Int | 1 for `check`; e.g. 4 for "Protein x4" |
| badDayTarget | Int | 1 for `check`; for `count`, 1 ≤ badDayTarget < target |
| unit | String? | "portions" |
| frequency | enum `daily`, `weekdays([Int])`, `perWeek(Int)` | perWeek is 1–7 |
| preferredWeekdays | [Int] | Only for perWeek: the days nudges may fire. Empty = no nudges. |
| setPointPerWeek | Int | Default = scheduled occurrences per week. Must be 1 … scheduled. |
| reminderTime | Int? | Minutes after midnight; nil = untimed |
| durationMinutes | Int | Used for feasibility. Default 15. |
| isPhysical | Bool | Physical habits may be scheduled on Saturdays |
| priority | Int | 1 (highest) to 5. Default 3. Decides which nudges win the daily cap. |
| isArchived | Bool | |
| createdAt | Date | |

Has many HabitLog (cascade). Sync: no.

### 3.7 HabitLog
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| habitID | UUID | |
| day | LocalDay | Unique together with habitID |
| mark | enum `D, B, M` | |
| count | Int? | Count habits only. The mark is derived from it: count ≥ target → D; ≥ badDayTarget → B; otherwise M. |
| loggedAt | Date | |

An unlogged scheduled occurrence in a finished day counts as M. It is computed, not stored. Sync: no.

### 3.8 WeekReview
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| goalID | UUID | |
| weekStart | LocalDay | A Monday. Unique together with goalID. |
| resultValue | Double? | Typed in at check-in |
| bottleneckHabitID | UUID? | |
| note | String? | |
| finishedAt | Date? | nil = still open |

Sync: no.

### 3.9 BlockRule (recurring block template)
id, planKey, systemID (UUID), title (String), durationMinutes (Int), weekdays ([Int]), startTime (Int), windowStart (Int), windowEnd (Int: the times it may be moved within), isPhysical (Bool), nudge (Bool, default false), active (Bool). Generates CalendarBlock instances (§5.3). Sync: no (its instances do).

### 3.10 CalendarBlock (one concrete block)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| ruleID | UUID? | nil = one-off block |
| systemID | UUID? | |
| goalID | UUID? | |
| title | String | |
| start, end | Date | |
| status | enum `scheduled, clash, done, cancelled` | |
| ignoredClashEventIDs | [String] | External events the user chose "Keep" against |
| suggestedStart | Date? | Set when status = clash |
| ekEventIdentifier | String? | |
| ekExternalIdentifier | String? | |
| lastSyncedAt | Date? | |
| isPhysical | Bool | |
| nudge | Bool | |

**Sync: yes**, two-way with the app's "Goals" calendar (§5).

### 3.11 PlanReminder (a one-off or repeating reminder from a plan)
id, planKey, systemID (UUID?), title (String), body (String), date (LocalDay?, one-off), weekdays ([Int], repeating), time (Int), priority (Int 1–5, default 3), active (Bool). Sync: no.

### 3.12 AppSettings (a single record)
| Field | Type | Default |
|---|---|---|
| morningTimeWeekday | Int | 450 (07:30) |
| morningTimeWeekend | Int | 540 (09:00) |
| eveningTime | Int | 1290 (21:30) |
| checkInWeekday | Int | 1 |
| checkInTime | Int | 1140 (19:00) |
| maxNotificationsPerDay | Int | 6 (fixed in MVP, shown read-only) |
| maxTimedNudgesPerDay | Int | 4 |
| bestHours | [TimeWindow] | Mon–Fri 08:00–10:00, 14:00–17:00 and 19:00–21:00; Sun 10:00–13:00 and 16:00–19:00. [OPEN]: the user adjusts these in onboarding. |
| saturdayOff | Bool | true |
| travelBufferMinutes | Int | 15 |
| goalsCalendarIdentifier | String? | |
| backupFolderBookmark | Data? | Security-scoped bookmark |
| lastBackupAt | Date? | |
| onboardingDone | Bool | false |

`TimeWindow { weekday: Int, start: Int, end: Int }`. Sync: no.

### 3.13 Runtime-only types (never stored)
`BusyInterval { start: Date, end: Date }`. `ExternalEvent { id, title, start, end, calendarColorHex, isAllDay }`. `PlannedNotification { id: String, fireDate: Date, title: String, body: String, link: DeepLink, kind }`. `Week { start: LocalDay }`. Score structs are in §4.6.

---

## 4. Goal creator

### 4.1 Flow
New goal (+) → Intake (4 rounds) → Review answers → **Send to Claude** → the user talks to Claude in the Claude app (his goal-system project) → Claude ends with a JSON plan → back in the app, **Import** (paste or `.json` file) → Import review → **Add to app** → habits, reminders and blocks become live.

### 4.2 Intake questions
Each round is one full-screen page with a progress bar (1/4 … 4/4). Every field is pre-filled with the default shown, so "Next" always works.

**Round 1: the goal**
1. "What do you want?" Text. Placeholder "10% body fat". Required.
2. "How will you measure it?" Result name (placeholder "Weigh-in average") plus unit (placeholder "kg"). Required.
3. "Where are you now?" Number.
4. "Where do you need to be?" Number. The direction (`up` / `down`) is inferred by comparing it with Q3.
5. "By when?" Date. Default today + 90 days.

**Round 2: your situation**
6. "What have you tried before, and why did it stop?" Text, optional.
7. "What do you have to work with?" Text. Placeholder "Uni gym, £30 a month, a friend who lifts".
8. "Any hard limits?" Text, optional. Placeholder "Knee injury, no cooking on Tuesdays".
9. "Why does this matter to you?" Text, optional.

**Round 3: time and place**
10. "Hours a week you can give this" Stepper 1–20, default 5.
11. "When do you work best?" Multi-select chips: Early 06–09, Morning 09–12, Afternoon 12–17, Evening 17–21, Late 21–24. Pre-selected from `AppSettings.bestHours`.
12. "Where do you work best?" Chips: Library, Home desk, Gym, Uni building, plus "Add". Multi-select.
13. "Keep Saturdays off for goal work?" Toggle, default on (physical habits still allowed).

**Round 4: what breaks it**
14. "What usually makes you stop?" Multi-select chips: Busy weeks, Boredom, No visible progress, Bad days, Other (text).
15. "What's the smallest version you'd still do on a bad day?" Text, optional.

Review page: each round collapsed into a card with an "Edit" link. Primary action: "Send to Claude".

### 4.3 Send to Claude
1. Build the prompt with `PromptBuilder.intakePrompt` (template in Appendix B). Busy times are taken from `CalendarServicing.busyIntervals` for the next 14 days, between 06:00 and 24:00, merged, and formatted `Mon 20 Oct: 09:00–11:00, 13:00–15:00`. Titles and locations are never included. If calendar access is denied, the line reads `Busy times: not available (calendar access off)`.
2. Copy the prompt to `UIPasteboard.general.string`.
3. Try `UIApplication.shared.open(URL(string: "claude://")!)`. [VERIFY] the Claude app's URL scheme; `claude` is listed in `LSApplicationQueriesSchemes`. If it fails, show the toast "Copied. Open Claude and paste it into your goal-system project."
4. Navigate to the Import screen for this draft. The intake answers are kept in memory (and in `@SceneStorage` as JSON) until an import succeeds or the user discards the draft.

### 4.4 Rules: plan JSON → app entities
The JSON schema is in Appendix A. `PlanImporter` does three things:

1. **Decode and validate.** Validation fails if any of these hold:
   - A `key` isn't unique within its array.
   - A reference names a key that doesn't exist.
   - A weekday is outside 1–7, or a time doesn't match `HH:mm`.
   - A date isn't ISO `YYYY-MM-DD`.
   - The `dependsOn` links form a cycle.
   - There isn't exactly one `sustaining` system.
   - A habit has `badDayTarget ≥ target` while `kind = count`.
   - A habit has `setPointPerWeek` larger than its scheduled occurrences.
   - A block's `windowStart > startTime` or `windowEnd < startTime + durationMinutes`.

   Errors are reported as `path: message` strings, and the first 5 are shown.
2. **Map.** `goal` → Goal; `firstPrinciples[]` → FirstPrinciple; `systems[]` → GoalSystem; `objectives[]` → Objective; `steps[]` → Step; `habits[]` → Habit; `blocks[]` → BlockRule (recurring) or CalendarBlock (one-off, with `date`); `reminders[]` → PlanReminder. Every entity gets `planKey = key`.
3. **Update mode.** If `goal.id` is present and matches an existing Goal, match the existing entities of that goal by `planKey`:
   - Same key: update the fields.
   - New key: insert.
   - Key missing from the JSON: archive habits (`isArchived = true`, so their logs are kept); delete block rules, their future blocks and their reminders; delete objectives and steps.
   - HabitLogs and WeekReviews are never touched.

After import: run back-scheduling (§4.5), then `CalendarServicing.sync()`, then `NotificationServicing.reschedule()`.

**Scheduling rules applied to imported habits and blocks:**
- No block is placed on a Saturday unless `isPhysical` (when `saturdayOff`). If the plan asks for a non-physical Saturday block, the importer moves it to Sunday at the same time and lists that in the Import review as "Moved off Saturday: Meal prep → Sun 17:00".
- A block that overlaps a busy interval when it is materialised gets status `clash` with a suggestion (§5.4). It isn't silently moved.

### 4.5 Back-scheduling (deadlines)
For each goal: `latestFinish(sink) = goal.deadline − bufferDays`, where a sink is an objective that nothing depends on. Working backwards in reverse topological order: `latestFinish(o) = min over successors s of (latestFinish(s) − s.estimatedDays)`. If `deadlineOverridden`, the stored date is kept and used in place of the computed one for its predecessors. Steps without their own deadline inherit the objective's.

**Warning:** if `latestFinish(o) − estimatedDays < today`, show "Starts N days too late" on that objective (ember text) in Map, Outline and Import review. This is a warning only; nothing is blocked.

### 4.6 Scores (used by the dashboard, Week tab and map colours)
For habit `h` in week `w`:
- `scheduled`: `daily` = 7, `weekdays(d)` = d.count, `perWeek(n)` = n.
- `done` = number of D or B logs in w. For perWeek habits, marks can be on any day and are capped at n.
- `bad` = number of B logs.
- `hit` = done ≥ setPointPerWeek.
- `badDayFlag` = done ≥ 2 and bad > done / 2.

For goal `g` in week `w` (over its non-archived habits):
- `onTarget` = count of habits with `hit`; `total` = habit count.
- `doneOcc` = Σ done; `schedOcc` = Σ scheduled; `setOcc` = Σ setPointPerWeek.
- `expectedSoFar` = ⌊ Σ_h setPoint_h × elapsed_h / scheduled_h ⌋. Here `elapsed_h` = scheduled occurrences on days before today, plus today's if the current time is past `eveningTime`. For perWeek habits, `elapsed_h = n × (days elapsed in the week) / 7`.
- **Dashboard gauge:** fill = doneOcc / schedOcc; set-point tick at setOcc / schedOcc; label "doneOcc of schedOcc"; colour **cobalt** if doneOcc ≥ expectedSoFar, otherwise **ember**.
- **Week tab gauge (finished week):** label "onTarget of total on target"; colour cobalt if onTarget == total, otherwise ember.
- **Goal streak:** consecutive finished weeks, ending last week, where onTarget == total. Display "N-week streak", or "no streak" when 0. A habit's streak uses the same rule with `hit`.
- **Suggested bottleneck:** the habit with the lowest done / setPoint last week. Ties go to the lower `priority` number, then to the earlier `sortIndex`.
- **System status (map colour):** cobalt if every habit in the system has done ≥ its pro-rata expected count this week, otherwise ember. Systems with no habits are neutral.

### 4.7 Feasibility (warning only)
`needed` = Σ over the goal's habits (durationMinutes × weekly occurrences) + Σ over block rules (durationMinutes × weekdays.count).
`free` = minutes inside `bestHours` over the next 7 days (Saturday excluded when `saturdayOff`), minus overlap with busy intervals, minus `needed` of all other active goals.

If `needed > 0.8 × free`, show the ember warning "This plan needs {needed h} a week. You have {free h} free in your best hours." in the Import review and the goal detail header. There is no forced action.

### 4.8 Showing and editing the DAG
**Map** (read-only, top to bottom, inside a zoomable scroll view from 0.6× to 2.0×):
- Layer 0: the Goal node (shows "Goal: {resultTarget} {unit}").
- Layer 1: first principles.
- Layer 2: principle systems, each under its principle.
- Layer 3 and below: objectives, placed by longest-path depth (objectives with no dependencies sit on layer 3).
- The sustaining system is a full-width node with a dashed border, pinned below the last layer.
- Edges are 1.2 pt lines in `#4A505B`: goal→principle, principle→system, system→objective, objective→dependent objective.
- Node width = (available width − gaps of 8 pt) / nodes in the layer, minimum 72 pt. Layers with more than 4 nodes scroll horizontally.
- Node style: map node component (§8.5). System nodes glow cobalt or ember by system status. Objectives show "done" in textSecondary with a check icon, and are ember if their deadline has passed and they aren't done.
- Tapping any node switches to Outline and scrolls to that row.

**Outline** (the only place where editing happens):
- Hierarchy: Principle → System → (Habit | Block rule | Reminder), then Milestones → Steps at the bottom, then the sustaining system and its children.
- Row icons (SF Symbols): principle `lightbulb`, system `gearshape.2`, habit `checkmark.square`, block `calendar`, reminder `bell`, milestone `flag`, step `circle`.
- The trailing badge shows: habit frequency ("daily", "M W F", "5/wk"); block time ("Sun 17:00"); milestone dependency ("after 82.0 kg" or "after 3 systems"), with any "Starts N days too late" warning shown under the title.
- Editing gestures: drag reorders within the same parent (updates `sortIndex`); swipe right indents and swipe left outdents, only where the new parent type is allowed.
- Tapping a row opens its editor sheet. Tapping a milestone's badge opens the dependency picker: a list of other objectives, where any choice that would create a cycle is disabled with the reason "Would create a loop".
- The toolbar "+" menu offers First principle, System, Habit, Block, Reminder, Milestone and Step.

---

## 5. Calendar

### 5.1 Built-in views
- **Week view:** 7 columns, Mon–Sun, 06:00–24:00, hour height 48 pt. Scrolls vertically; pages horizontally week to week.
- **Day view:** one column, hour height 64 pt.
- A segmented control in the navigation bar's principal slot switches Day and Week. A "Today" toolbar button jumps to now.
- The current time is a 1 pt cobalt line with a 6 pt dot.
- Saturday columns have a `#FFFFFF` 3% fill and an "Off" label when `saturdayOff`.
- **Content per item type:**
  - External events: fill `#23252B`, a 3 pt leading bar in the event's calendar colour, title in textSecondary at 12 pt. All-day events go in a top strip.
  - Goal blocks: fill `#182553`, a 3 pt leading bar in `#3D6BFF`, title in textPrimary at 12 pt.
  - Blocks with status `clash`: 1.5 pt border `#FF2D17` plus a "Clash" chip.
  - Blocks with status `done`: fill `#1E2026`, title in textSecondary.
  - Timed habits: 20 pt chips with a 1 pt outline in `#4A505B`, placed at their reminder time.
- **Interactions:**
  - Tap a block → Block sheet (title, goal, time; actions "Done", "Move", "Delete").
  - Tap a clash → Conflict sheet.
  - Tap a habit chip → mark sheet.
  - Long-press an empty slot → New block sheet (title, system picker, duration, start, defaulting to the press time rounded down to 15 min).
- Month view is a later feature.

### 5.2 What syncs in each direction
| Direction | What | Rule |
|---|---|---|
| Apple → app (read) | Events from every calendar except Goals | Used as busy intervals and shown in the Calendar tab. Events with `availability == .free` and all-day events are excluded from busy intervals. Never stored in SwiftData. |
| App → Apple (write) | CalendarBlocks with status `scheduled` or `clash` from now to +14 days | Created or updated in the Goals calendar. `cancelled` blocks: their event is deleted. Blocks in the past are never touched. |
| Apple → app (write-back) | Changes to events in the Goals calendar | Time changed → block start/end updated. Title changed → block title updated. Event deleted → block status `cancelled`. Apple Calendar wins for these three fields. |

Event fields written: `title = block.title`; `notes = "Lock in · {goal title}\nid:{block.id}"`; `url = lockin://block/{block.id}`; no alarms (so blocks never add notifications outside the cap). Events are matched by `ekEventIdentifier`, falling back to parsing `id:` from the notes.

### 5.3 Which calendar the app writes to
- On first calendar access the app creates an `EKCalendar` titled **"Goals"** with colour `#3D6BFF`. Its source is `eventStore.defaultCalendarForNewEvents?.source`; if that isn't writable, the first source of type `.local`. The identifier is stored in `AppSettings.goalsCalendarIdentifier`.
- If the user deletes the Goals calendar, the next sync recreates it and rewrites all future blocks.
- The user keeps Apple Calendar for fixed things only, so onboarding shows the tip: "In Apple Calendar, tap Calendars and untick Goals. Your blocks stay in this app's Calendar tab." EventKit can't hide a calendar itself. [VERIFY] that hidden calendars still sync events through EventKit.
- **Materialising block rules:** for each active BlockRule, create one CalendarBlock per matching weekday from today to today + 14 days, unless a block for that rule and date already exists. Recurrence is never written as an `EKRecurrenceRule`; each instance is its own event so a single instance can be moved.

### 5.4 Conflict rules
- **Busy intervals:** external events expanded by `travelBufferMinutes` on both sides.
- **Clash:** a future block with status `scheduled` overlaps a busy interval whose event ID isn't in `ignoredClashEventIDs` → status `clash`.
- **Suggestion** (`ScheduleEngine.suggestSlot`): the earliest free interval of the same duration, searched in this order:
  1. The same day, inside the rule's `windowStart…windowEnd` (one-off blocks use the day's `bestHours`).
  2. The same window on following days, up to 7 days ahead.
  3. Skipping Saturdays unless `isPhysical`.
  4. Never overlapping other blocks.

  The result is stored in `suggestedStart`. If there is none: "No free slot this week".
- **Conflict sheet:** shows "{event title} now overlaps {block title}", the suggested slot, and the buttons "Move" (primary), "Keep" (adds the event ID to `ignoredClashEventIDs`, status back to `scheduled`) and "Pick another time" (time picker).
- Nothing is moved without a tap.
- The Today accessory shows a "1 clash" chip while any clash exists in the next 7 days.

### 5.5 Sync triggers
App launch, scene becoming active, `EKEventStoreChanged`, after any block edit, and after import. The sync sequence is:
1. Read external events for now−1 day to +14 days.
2. Pull Goals calendar changes.
3. Materialise rules.
4. Detect clashes.
5. Push blocks.
6. Call `NotificationServicing.reschedule()`.

A sync must finish within 2 s for 200 events.

---

## 6. Reminders

### 6.1 Notification types and default times
| Kind | When | Condition |
|---|---|---|
| Morning | `morningTimeWeekday` Mon–Fri, `morningTimeWeekend` Sat–Sun | At least 1 habit or block today |
| Timed habit | `reminderTime` | Habit scheduled today, not yet marked D or B, and (for perWeek) on a `preferredWeekday` and still short of `perWeek` |
| Block nudge | 10 min before start | `nudge == true` and status `scheduled` |
| Plan reminder | Its date or weekdays at `time` | `active` |
| Evening tick-off | `eveningTime` | At least 1 scheduled habit today still unmarked |
| Check-in | `checkInWeekday` at `checkInTime` | Last week's review not finished |
| Re-sign | Later of (expiry − 48 h) and (now + 1 min) | Signing expiry is known and within 7 days. One notification only. |

### 6.2 Daily cap and priority
At most 6 notifications per day: Morning (1) + Evening (1) + up to 4 "timed slots". On the check-in day, the check-in takes one timed slot (so 3 remain).

Timed habits, block nudges and plan reminders compete for the timed slots by `priority` ascending, then fire time ascending. Losers are dropped for that day; they still appear in the morning summary and evening tick-off. The re-sign notification sits outside the cap.

### 6.3 Handling the 64-notification limit
- **Window:** `ReminderPlanner.plan` builds every regular notification for now → now + 10 days, sorted by fire date, and keeps the first **60** (6 a day × 10 days). The re-sign notification, if any, is added on top, so there are at most 61 pending, 3 under iOS's 64 limit.
- **Reschedule** (`NotificationServicing.reschedule()`) calls `removeAllPendingNotificationRequests()` and then adds the planned set.
- **When it runs:** app launch, scene active, after every mark, after any edit to habits, blocks, reminders or settings, after calendar sync, after import, after restore.
- **Horizon warning:** the evening notification on the last planned day appends " Open the app to keep reminders coming."
- **Identifiers:** `morning-YYYY-MM-DD`, `evening-YYYY-MM-DD`, `checkin-YYYY-MM-DD`, `habit-{uuid}-YYYY-MM-DD`, `block-{uuid}`, `reminder-{uuid}-YYYY-MM-DD`, `resign`.
- **Trigger:** `UNCalendarNotificationTrigger(dateMatching: year, month, day, hour, minute, repeats: false)`. Interruption level `.active`, default sound, no `categoryIdentifier` (no action buttons).

### 6.4 Notification text (exact templates)
| Kind | Title | Body |
|---|---|---|
| Morning | `Today.` | `{nBlocks} blocks, {nHabits} habits. First: {firstTitle} at {HH:mm}.` If nothing is timed: `{nHabits} habits today.` Leave out "0 blocks, ". |
| Timed habit | `{title}.` | `{HH:mm}{ at {location}}. Bad day: {badDayTitle}.` |
| Block nudge | `{title}.` | `Starts {HH:mm}, {durationMinutes} min.` |
| Plan reminder | `{title}` | `{body}` |
| Evening | `Tick off today.` | `{k} left: {t1}, {t2}, {t3}{ +{k−3} more}.` |
| Check-in | `Check-in.` | `Last week: {Σ onTarget} of {Σ total} on target. About 5 minutes.` |
| Re-sign | `Re-sign Lock in.` | `It stops opening {EEE d MMM} at {HH:mm}. Your data is safe. Plug in and run Sideloadly.` |

Example: `Incline walk.` / `08:15 at the gym. Bad day: 20 min walk.`

### 6.5 Tap, snooze and skip
- Each notification's `userInfo["link"]` holds a DeepLink URL. Tapping routes to:
  - habit → `lockin://habit/{uuid}?day=YYYY-MM-DD` (opens the mark sheet)
  - morning → `lockin://today`
  - evening → `lockin://today`
  - check-in → `lockin://week`
  - block → `lockin://block/{uuid}`
  - re-sign → `lockin://settings`
- **Snooze:** not in MVP (no action buttons, by user decision).
- **Skip:** the user marks M in the mark sheet. That cancels the day's nudge on the next reschedule.
- **Missed timed habits:** no second nudge. They show up in the evening tick-off.

---

## 7. Screens

Global: 4 tabs from the system `TabView`, in this order: **Goals** (`target`), **Calendar** (`calendar`), **Habits** (`checklist`), **Week** (`chart.bar`). Every tab root uses `NightCanvas` (§8.6). Each tab has its own `NavigationStack`. Sheets are presented from a single `Router.sheet`.

Permission-denied states use one shared component, `PermissionBanner(title, body, action: "Open Settings")`, which opens `UIApplication.openSettingsURLString`.

### 7.1 Onboarding (first launch only, full-screen cover)
- **Purpose:** permissions, then setup.
- **Pages:**
  1. "Lock in." with a one-line description and "Start".
  2. Notifications explainer: "Up to 6 a day: a morning plan, a few timed nudges, an evening tick-off." → system prompt.
  3. Calendar explainer: "Reads your calendars to find free time. Writes only to a new Goals calendar." → `requestFullAccessToEvents`.
  4. Best hours: editable `TimeWindow` list, pre-filled with the defaults.
  5. Backup folder: "Choose folder" (`UIDocumentPickerViewController` for folders) or "Later".
  6. Tip: hide Goals in Apple Calendar (§5.3). → "Done" sets `onboardingDone`.
- **Errors:** a denied permission just continues to the next page.

### 7.2 Goals tab (home): `GoalsDashboardView`
- **Purpose:** see every goal at a glance.
- **Components:**
  - Large title "Goals." with the date as a subtitle ("Mon 19 Oct") above it.
  - Toolbar trailing: Settings (`gearshape`), `ToolbarSpacer(.fixed)`, New goal (`plus`, `.glassProminent`).
  - Re-sign banner (when expiry is within 48 h).
  - Monday check-in banner: solid; fill `#3D6BFF` at 10%, 1 pt `#8FB0FF` at 28%; text "Check-in tonight, {HH:mm}" before check-in time, "Check-in ready" after. Tap → Week tab.
  - `GoalTile` list, sorted by `sortIndex`. Each shows the title with a full stop, days left, a `ProgressGauge`, "result, target" (latest WeekReview resultValue, else resultStart), the streak and "Bottleneck: {habit title}" (hidden if none).
  - Long-press a tile → menu: Pause, Mark achieved, Drop, Reorder.
- **Navigation:** tile → Goal detail. Plus → Intake (sheet). Settings → push.
- **Empty:** headline "Build your first system", body "Answer a few questions and Claude turns your goal into habits and calendar blocks.", button "New goal".
- **Errors:** store load failure → "Your data couldn't load. Restore from a backup." + "Restore" (Settings → Restore).
- **Calendar denied:** banner "Calendar access is off. Turn it on so plans fit your timetable."

### 7.3 Today accessory and Today sheet: `TodayAccessoryView`, `TodaySheet`
- **Accessory [OPEN, recommended]:** placed with `.tabViewBottomAccessory`, so it shows on every tab. [VERIFY] the API name on the SDK in use. If it isn't available, render the same content as the first row of the Goals list (solid style).
  - Content: a clock icon, "{next item title}, {HH:mm}", then on the trailing side "{n} left" and a "1 clash" chip if relevant.
  - If nothing is left today: "All done today."
  - Tap → TodaySheet.
- **TodaySheet** (detents medium and large): today's timeline. Items with a time, in order (blocks, timed habits), then untimed habits. Each row has a mark dot. Tap a habit → mark sheet; tap a block → Block sheet.
- **Empty:** "Nothing planned today."

### 7.4 Mark sheet: `HabitMarkSheet(habitID:day:)`
- **Detents:** `.height(220)` for check habits, `.height(300)` for count habits. System sheet: no `presentationBackground`.
- **Components:**
  - Header: habit title, and the day "Today" / "Yesterday" / "Mon 19 Oct", tappable to change it (only within the current and previous week while the review is unfinished).
  - Check habits: three large buttons in a row:
    - **D** "Done" (cobalt dot)
    - **B** "{badDayTitle}" (silver dot)
    - **M** "Missed" (hollow dot)
  - Count habits: a stepper (− {count} +) showing "Target {target}, bad day {badDayTarget}" and the derived mark.
  - "Clear mark" text button.
- **Behaviour:** tapping a mark saves, plays its haptic and closes the sheet. A count change saves after 0.6 s of no taps.
- **Errors:** save failure → inline "Couldn't save. Try again."

### 7.5 Goal detail: `GoalDetailView(goalID:)`
- **Components:**
  - Navigation title "{goal title}." and subtitle "{deadline d MMM}, {n} days left".
  - Feasibility warning (when it applies).
  - A segmented control **Map | Outline**, defaulting to Map.
  - Map and Outline as described in §4.8.
  - Toolbar: Map shows `pencil`, which switches to Outline; Outline shows "+" (add menu) and "Done".
  - The goal header row (in Outline) opens the Goal editor: title, outcome, deadline, result fields, buffer days, status.
- **Empty** (a goal with no systems): "No systems yet", with buttons "Import a plan" and "Add a first principle".
- **Errors:** an editing cycle is prevented (§4.8).

### 7.6 Intake flow: `IntakeFlowView`
As in §4.2, presented as a sheet with large detents. "Cancel" asks "Discard this goal?" (Discard / Keep editing).

### 7.7 Import: `ImportPlanView(goalID: UUID?)`
- **Empty state:** "Paste the JSON Claude gave you", with "Paste" (reads the clipboard) and "Open file" (`.fileImporter`, `UTType.json`).
- **Parsing:** shows a spinner.
- **Error:** an ember box listing up to 5 errors plus "Copy errors" (so the user can paste them back to Claude).
- **Success → Import review:**
  - Counts of first principles, systems, habits, blocks and reminders.
  - The "Moved off Saturday" list.
  - Clashes.
  - Feasibility warning.
  - "Starts N days too late" list.
  - In update mode: "Updates {goal}: +{n} new, {m} changed, {k} removed".
  - Primary button "Add to app" (or "Update goal").
- Opening a `.json` file from outside the app routes here through `.onOpenURL`.

### 7.8 Calendar tab: `CalendarTabView`
- As described in §5.1.
- **Calendar denied:** the grid shows only the app's blocks, with a PermissionBanner at the top.
- **Empty:** the grid is always shown; there is no separate empty state.
- **Sync error:** a toast "Calendar didn't sync. Pull to retry." (pull to refresh calls `sync()`).
- **Sheets:** Block sheet, Conflict sheet `ConflictSheet(blockID:)`, New block sheet.

### 7.9 Habits tab: `HabitsTabView`
- **Purpose:** manage habits.
- **Components:**
  - Title "Habits."
  - Sections per goal, plus "Standalone".
  - Row: title, frequency text, "this week {done}/{setPoint}", streak, and a mark dot for today.
  - Tapping the dot opens the mark sheet; tapping the row opens the Habit editor (push).
  - Toolbar "+" adds a standalone habit.
  - Swipe action: Archive.
  - A "Show archived" toggle at the bottom.
- **Habit editor fields:**
  - Title and bad-day title.
  - Kind; target and bad-day target (count only).
  - Unit.
  - Frequency picker: Daily / Days (7 weekday toggles) / Times a week (stepper 1–7 plus preferred-day toggles).
  - Set point (stepper 1…scheduled).
  - Reminder (toggle + time), duration, physical toggle, priority (1–5).
  - System picker (optional).
- **Empty:** "Add your first habit", body "Or build a goal and Claude will suggest them.", buttons "Add habit" and "New goal".
- **Notifications denied:** banner "Reminders are off. Habits still track, but nothing will nudge you."

### 7.10 Week tab: `WeekTabView`
- **Purpose:** the weekly check-in and history.
- **Default view:** last finished week (Mon–Sun) on Mondays from 00:00 until the review is finished; otherwise the current week (live, not reviewable). Toolbar chevrons step back through finished weeks (read-only).
- **Components:**
  - Title "Week." with subtitle "{d} to {d MMM}".
  - Per goal, a solid tile:
    - Title.
    - Score label "{onTarget} of {total} on target", in ember or cobalt.
    - A grid with a header row M T W T F S S + "set", then one row per habit: name, 7 mark dots (D cobalt with glow, B `#A3ABB8`, M hollow `#4A505B` 1.5 pt, not scheduled = 6×2 pt dash `#3A3F48`), and "{done}/{setPoint}" (ember when below).
    - Flags: an ember box "{habit}: {bad} of {done} were B. The slot may be in the wrong place."
    - A Result field ("{resultName}", decimal keyboard, unit suffix, delta from the last value).
    - A Bottleneck picker (menu, pre-set to the suggestion).
    - An optional Note field.
  - Other goals collapse to a single row (title + score), and expand on tap.
  - Floating control cluster above the tab bar (`GlassEffectContainer`): **"Send to Claude"** (`.glass`) and **"Finish"** (`.glass`).
- **Send to Claude:** `PromptBuilder.checkInPrompt` (Appendix C) for the expanded goal → clipboard → open Claude (as in §4.3) → then Import (update mode, with the goal ID).
- **Finish:** saves every WeekReview for that week with `finishedAt = now`, runs `BackupServicing.backUpNow()` (if a folder is set; otherwise toast "Backup skipped. Choose a folder in Settings."), reschedules notifications and shows the toast "Week saved".
- **Empty** (no goals): "No goals to review yet."

### 7.11 Settings: `SettingsView` (pushed from Goals)
**Sections:**
- **Times:** morning weekday, morning weekend, evening, check-in day and time.
- **Best hours:** TimeWindow list editor.
- **Planning:** Saturday off toggle, travel buffer stepper (0–60, step 5).
- **Calendar:** access status, and a "Goals calendar" row showing the calendar name or "Not created".
- **Notifications:** access status.
- **Backup:** folder name or "None"; "Choose folder"; "Back up now"; "Restore from file…" (confirmation alert: "Replace everything in the app with this backup?").
- **Signing:** "App expires {EEE d MMM HH:mm}", or "Unknown" [VERIFY parsing].
- **Claude:** "Copy prompt add-on" (copies the Appendix A instructions for the user's goal-system prompt).
- **Diagnostics:** pending notifications count, last sync time, app version and build.

Every change saves immediately.

---

## 8. Design system ("Night glass")

Dark only. `Info.plist`: `UIUserInterfaceStyle = Dark`; apply `.preferredColorScheme(.dark)` at the root. There are no light-mode tokens: light mode is not needed by decision.

### 8.1 Colour tokens (Swift `Color` extensions in `DesignSystem/Tokens.swift`)
| Token | Hex / value | Use |
|---|---|---|
| canvas | `#050608` | Base background |
| canvasGlow | Radial gradient: `#2A52D6` 0%, `#10204F` 38%, `#07090F` 72%, `#050608` 100%. Ellipse 130% × 55% of the screen, centred at x 50%, y −12%. | Top glow on every tab root |
| horizonGlow | `#1A2A5C` at 60% opacity, radial, centred at the bottom edge, covering the lower 30% of the screen, fading to clear | Gives the tab bar light to refract |
| tileTop / tileBottom | `#2B2D33` → `#17181C`, vertical linear | GoalTile and Week tiles |
| tileStroke | `#FFFFFF` at 9%, 1 pt | Tile border |
| separator | `#FFFFFF` at 6%, 1 pt | Rows inside tiles |
| field | fill `#FFFFFF` 6%, stroke `#FFFFFF` 14% 1 pt | Inputs, pickers inside content |
| textPrimary | `#F2F4F7` | |
| textSecondary | `#A3ABB8` | |
| textTertiary | `#7C8494` | Captions (changed from the mockups' `#6B7280` to pass 4.5:1 on tiles) |
| cobalt (accent) | `#3D6BFF` | App tint, selected tab, gauge fill base, D dots |
| cobaltText | `#8FB0FF` | Cobalt-coloured text on dark backgrounds |
| cobaltFill | Radial: `#9DB6FF` 0% at x 12% → `#3D6BFF` 38% → `#2448E0` 100% | Gauge fill, on track |
| cobaltGlow | `#3D6BFF`, shadow radius 20, opacity 0.75 | Behind the cobalt gauge fill; tile under-glow at radius 30, y 14, opacity 0.55 |
| ember | `#FF2D17` | Behind-state base |
| emberText | `#FF6A4D` | Ember text |
| emberFill | Radial: `#FF7A5C` 0% at x 18% → `#FF2D17` 45% → `#D91A0B` 100% | Gauge fill, behind |
| emberEdge | `#FF8A1A` | 2 pt trailing edge on the ember fill |
| emberGlow | `#FF3B1F`, radius 20, opacity 0.75 | |
| markB | `#A3ABB8` | B dot |
| markMStroke | `#4A505B` | M dot outline, map edges |
| notScheduled | `#3A3F48` | Dash |
| gaugeTrack | fill `#FFFFFF` 5%, stroke `#FFFFFF` 14% 1 pt, dot grid `#FFFFFF` 7% (1 pt dots, 5 pt pitch) | |
| blockFill | `#182553` | Goal blocks in the calendar |
| eventFill | `#23252B` | External events |

Contrast: textSecondary on tileBottom ≈ 7.6:1; textTertiary ≈ 4.7:1; cobaltText ≈ 8:1; emberText ≈ 6:1. `cobalt` itself is never used for text under 17 pt.

Glow colour meaning: **cobalt = at or above the set point (or pro-rata expected); ember = behind.** Ember is never used for decoration.

### 8.2 Type scale
SF Pro (system). Every style maps to a Dynamic Type text style, so it scales.

| Token | Text style | Size at default | Weight | Tracking |
|---|---|---|---|---|
| screenTitle | `.largeTitle` (navigation large title) | 34 | Bold | −0.5 |
| tileTitle | `.title2` | 22 | Semibold | −0.3 |
| sectionTitle | `.headline` | 17 | Semibold | 0 |
| body | `.body` | 17 | Regular | 0 |
| callout | `.callout` | 16 | Regular | 0 |
| subhead | `.subheadline` | 15 | Regular | 0 |
| footnote | `.footnote` | 13 | Regular | 0 |
| caption | `.caption` | 12 | Regular | 0 |
| caption2 | `.caption2` | 11 | Regular | 0 |
| gaugeNumber | `.subheadline` | 15 | Medium, `.monospacedDigit()` | 0 |

**Title voice:** screen titles and goal titles end with a full stop ("Goals.", "Week.", "10% body fat."). Add the full stop in the display layer only; never store it in the data.

### 8.3 Spacing, radii and sizes
- **Spacing scale:** 4, 8, 12, 16, 20, 24, 32 pt. Screen side margin 16. Gap between tiles 12. Tile padding 18 horizontal, 16 vertical. Row vertical padding 8.
- **Radii** (all `.continuous`): tile 28, map node 14, field 10, Week flag box 14, chips and gauge = capsule.
- **Gauge:** height 38, full tile width. Set-point tick: 1 pt `#FFFFFF` at 45%, inset 6 pt top and bottom. Label inside, right-aligned, 14 pt from the end.
- **Mark dot:** 13 pt (Week grid), 16 pt (rows). **Touch targets:** at least 44 × 44.

### 8.4 Haptics (`.sensoryFeedback`)
| Event | Feedback |
|---|---|
| D marked | `.success` |
| B marked | `.impact(weight: .light)` |
| M marked or mark cleared | `.selection` |
| Check-in finished | `.success` |
| Block moved after a clash | `.impact(weight: .medium)` |
| Outline reorder or indent | `.selection` |
| Import failed | `.error` |

### 8.5 Core components (in `DesignSystem/Components/`)
| Component | API | Spec |
|---|---|---|
| `NightCanvas` | `NightCanvas { content }` | canvas + canvasGlow + horizonGlow + grain, ignoring safe areas |
| `GrainOverlay` | internal | A 256×256 monochrome noise image generated once at launch with CoreGraphics (fixed seed 42), tiled, opacity 0.08. Used only inside NightCanvas. |
| `GoalTile` | `GoalTile(title:, daysLeft:, gauge: GaugeModel, resultText:, streakText:, bottleneck: String?)` | Tile gradient, stroke, radius 28, under-glow in the gauge's state colour |
| `ProgressGauge` | `ProgressGauge(model: GaugeModel)` where `GaugeModel { fraction: Double, setPoint: Double?, label: String, state: .onTrack/.behind/.neutral, lowLabel: String?, highLabel: String? }` | Track + fill + glow + tick + label. Scale labels above it in caption2 textTertiary ("0", "set point", "12"). |
| `MarkDot` | `MarkDot(mark: Mark?, scheduled: Bool, size:)` | As described in §7.10 |
| `HabitRow` | `HabitRow(title:, subtitle:, mark:, onTapMark:, onTapRow:)` | |
| `TitleText` | `TitleText("Goals")` | Appends the full stop and applies screenTitle or tileTitle |
| `FlagBox` | `FlagBox(text:)` | Fill `#FF2D17` 10%, stroke 35%, icon `flag`, emberText-tinted text `#FFB4A3` |
| `PermissionBanner` | See §7 | Solid; fill `#FFFFFF` 6% |
| `MapNode` | `MapNode(title:, state: .onTrack/.behind/.done/.neutral, dashed: Bool)` | Radius 14, tile gradient, 1 pt stroke; glow 10 pt in the state colour |
| `Toast` | `.toast(text: Binding<String?>)` | Solid capsule at the top, shown for 2.5 s |

### 8.6 Motion
- Gauge fill changes: `.spring(response: 0.5, dampingFraction: 0.8)`.
- Mark dot change: scale 0.8 → 1.0 over 0.2 s.
- Tile insertion: `.opacity` + `.move(edge: .bottom)`, 0.3 s.
- Sheet and navigation transitions: system defaults.
- **Reduce Motion on:** springs become `.easeInOut(duration: 0.2)` and moves become crossfades.

### 8.7 Liquid Glass
**Principle.** Glass is the control layer: the things you press to move around float above goals and habits and bend their light. It stops at content. Goal tiles, gauges, habit rows, calendar cells, the Week grid, banners and flags are solid and drawn in the palette above. Only one layer of glass is ever on screen at a time, and nothing that carries data is glass.

**Where glass goes:**
| Surface | Implementation |
|---|---|
| Tab bar | System `TabView` + `Tab("Goals", systemImage: "target", value: AppTab.goals)` and so on. Leave the minimise behaviour at its default. |
| Today accessory | `.tabViewBottomAccessory { TodayAccessoryView() }` (system glass). [VERIFY] |
| Navigation bars and toolbar items | System. New goal uses `.buttonStyle(.glassProminent)`, the only prominent glass button in the app. [VERIFY] that it renders as prominent inside a toolbar. `ToolbarSpacer(.fixed)` separates it from Settings. |
| Sheets | System `.sheet` with `.presentationDetents`; never `.presentationBackground`. |
| Week tab action cluster | `GlassEffectContainer(spacing: 24)` holding two buttons with `.buttonStyle(.glass)`, each with `.glassEffectID(_, in: ns)` for morphing. |
| Custom floating shapes | Only via `.glassEffect(.regular.interactive(), in: .capsule)` inside a `GlassEffectContainer`. There are none in the MVP besides the Week cluster. Containers are never nested. |

**Accent and tint:** `.tint(.cobalt)` at the root drives the selected tab, the lens icons and the prominent button. All other glass stays untinted. `.glassEffect(.regular.tint(...))` is used on 0 controls in the MVP (cap: 1). Ember never appears on glass.

**Backgrounds:** every tab root uses NightCanvas, so the bottom of each screen has horizonGlow for the tab bar to refract. Every scroll view extends under the tab bar (no bottom safe-area clipping of content). Screens flagged as needing this: Habits (a short list leaves the bottom empty) and Calendar (empty evenings).

**Banned:** `.ultraThinMaterial` and every other `Material`; `.blur` used to imitate glass; gradient or white-stroke overlays that imitate glass; custom tab bars; `.toolbarBackground(...)` colours; `UITabBarAppearance` backgrounds; glass on content. The HTML mockups in the design session faked glass; build from this section, not from the mockups.

**Build:** compile with Xcode 26 or later (iOS 26 SDK). Deployment target iOS 26.0. Do not set `UIDesignRequiresCompatibility`. Reduce Transparency and Increase Contrast are left to the system.

### 8.8 Dynamic Type and VoiceOver rules
- All text uses the text styles in §8.2; no fixed font sizes. Test at the default size, at xxxLarge and at AX3.
- At accessibility sizes (`dynamicTypeSize.isAccessibilitySize`):
  - Week grid rows become two lines (habit name, then the 7 dots + score).
  - GoalTile stacks its title and days left.
  - Map node labels may wrap to 3 lines; nodes grow taller, never truncate.
- **VoiceOver labels:**
  - ProgressGauge: "This week, 9 of 12 done, set point 8, on track" (or "behind").
  - MarkDot: "{weekday}, done" / "bad-day version" / "missed" / "not scheduled".
  - GoalTile: one combined element "{title}, {days} days left, {gauge label}, result {resultText}, {streak}"; double tap opens it.
  - Map: nodes are read in layer order with the label "{type}: {title}, {state}".
  - Outline rows have custom actions: "Move up", "Move down", "Indent", "Outdent", "Edit".
  - Week tab: the flag box is read first in its tile.
- Decorative glows and grain are `.accessibilityHidden(true)`.

---

## 9. Sideloading and permissions

### 9.1 Account-dependent features (free Apple ID)
| Feature | Status |
|---|---|
| Local notifications (UserNotifications) | Works without capabilities. Used. |
| EventKit read/write | Needs only the Info.plist usage string. Used. |
| SwiftData local store | Works. Used. |
| Custom URL scheme `lockin://` and `.json` document type | Info.plist only. Used. |
| Files folder access for backups (security-scoped bookmark) | Used. [VERIFY] that writing to an iCloud Drive folder works without the iCloud capability. |
| Background App Refresh (`BGAppRefreshTask`) | **[needs account check]**. Not in MVP; the 10-day notification horizon makes it unnecessary. |
| App Groups, widgets, share extension | **[needs account check]**. Later. |
| App Intents / Siri | **[needs account check]**. Later. |
| iCloud / CloudKit sync, remote push | **[needs account check]**. Not used. |
| Time Sensitive notifications | **[needs account check]**. Not used; interruption level `.active`. |

Single target, no extensions: a free Apple ID is limited in the number of app IDs per week and active sideloaded apps [VERIFY the current limits], and extensions use extra app IDs.

### 9.2 Permission prompts
| Permission | When | Info.plist key and text |
|---|---|---|
| Notifications | Onboarding page 2, after "Allow reminders" is tapped. If not determined later, again when a reminder is first enabled on a habit. | No key. Request `[.alert, .sound, .badge]`. |
| Calendar (full access) | Onboarding page 3, after "Connect calendar". If denied, re-prompting is impossible; show the Settings link. | `NSCalendarsFullAccessUsageDescription`: "Lock in reads your calendars to find free time around your timetable and writes goal blocks to its own Goals calendar." |
| Files folder | Onboarding page 5 or Settings → Backup. Not a system permission prompt. | None |

### 9.3 Identity and data persistence across re-signing
- **Bundle ID:** `com.youssoufdiallo.lockin` [OPEN, but it must never change once the first build is installed]. Display name "Lock in" [OPEN]. URL scheme `lockin`.
- **Where data lives:** SwiftData store in the app container (`Application Support/LockIn.store`). The data survives re-signing because the user re-installs over the existing app with **Sideloadly on Windows, using the same Apple ID, every time**, and Sideloadly's option to change the bundle ID stays **off**. [VERIFY] the option name in Sideloadly.
- **What would cause data loss:** a different bundle ID or team ID produces a new, empty container. Deleting the app deletes its data.
- **Expiry:** after 7 days the app won't open, but the data stays until it is re-signed. [VERIFY] whether already-scheduled notifications still fire while the app is expired.
- **Expiry detection:** at launch, `SigningInfo.expiryDate()` reads `Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")`, extracts the bytes between `<?xml` and `</plist>`, parses them with `PropertyListSerialization` and reads `ExpirationDate`. If this returns nil, show "Unknown" and skip the warning. [VERIFY]
- **Re-sign warning:** banner (§7.2) + one notification (§6.1).
- **Backup:** automatic JSON after each check-in (§7.10).
  - File name `lockin-backup-YYYY-MM-DD.json`, also copied to `lockin-backup-latest.json` in the chosen folder.
  - Dated files older than 8 weeks are deleted by the app (only files matching that name pattern).
  - Format: Appendix D.
  - Restore replaces the whole store and then runs sync and reschedule.

### 9.4 Build and install pipeline
- **Repository layout:** see §10. The Xcode project is generated by **XcodeGen** from `project.yml`; the `.xcodeproj` is never committed. Folder-based sources mean adding a file never edits a shared project file.
- **CI** (`.github/workflows/build.yml`), on every push to `main` and manually:
  - Job `core-tests` (`ubuntu-latest`): install Swift 6.1 or later, then `swift test --package-path Packages/CoreKit`.
  - Job `ios-build` (`macos-26`):
    1. `brew install xcodegen`
    2. `xcodegen generate`
    3. `xcodebuild -project LockIn.xcodeproj -scheme LockIn -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/LockIn.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
    4. `mkdir Payload && cp -R build/LockIn.xcarchive/Products/Applications/LockIn.app Payload/ && zip -qry LockIn.ipa Payload`
    5. Upload `LockIn.ipa` as an artifact.
  - `ios-build` must also print `xcodebuild -version` and fail if the major version is below 26.
- **Minutes:** GitHub's free macOS minutes for private repos are limited [VERIFY the current allowance]. The Linux job catches logic errors cheaply. [OPEN] Recommend a public repository (it contains no personal data) for free standard-runner minutes.
- **Install:** download the artifact on the Windows PC → Sideloadly → the same Apple ID → install over the existing app.

---

## 10. Build modules

7 modules. Every path belongs to exactly one module. The app target compiles `App/**` plus the CoreKit package. Feature modules talk to each other only through `App/Shared` (Router, AppServices) and CoreKit types; they never import each other's files.

### 10.1 Repository tree and ownership
```
/project.yml                                   M7
/.github/workflows/build.yml                   M7
/README.md                                     M7
/Packages/CoreKit/Package.swift                M1
/Packages/CoreKit/Sources/CoreKit/**           M1
/Packages/CoreKit/Tests/CoreKitTests/**        M1
/App/Shared/**                                 M7 (contract files, written in wave 1)
/App/Shell/**                                  M7
/App/Resources/Info.plist                      M7
/App/Resources/Assets.xcassets/**              M7
/App/Services/Notifications/**                 M7
/App/Persistence/**                            M2
/App/DesignSystem/**                           M3
/App/Features/Habits/**                        M4
/App/Features/Week/**                          M4
/App/Features/Today/**                         M4
/App/Features/Goals/**                         M5
/App/Features/Calendar/**                      M6
/App/Services/Calendar/**                      M6
```

### 10.2 Modules

**M1 · CoreKit (pure Swift package; compiles and tests on Linux)**
- **Owns:** `Packages/CoreKit/**`.
- **Rules:** may import only `Foundation`. No SwiftUI, SwiftData, EventKit, UserNotifications or UIKit. Swift tools version 6.0, iOS 26 / macOS 15 platforms declared.
- **Public interface:**
  - **Domain:** structs from §3 (`Goal`, `FirstPrinciple`, `GoalSystem`, `Objective`, `Step`, `Habit`, `HabitLog`, `WeekReview`, `BlockRule`, `CalendarBlock`, `PlanReminder`, `AppSettings`, `TimeWindow`, `BusyInterval`, `ExternalEvent`, `LocalDay`, `Week`), plus `enum Mark { D, B, M }`, `enum Frequency`, `enum DeepLink { habit(UUID, LocalDay), today, week, goal(UUID), block(UUID), settings }` with `init?(url:)` and `var url`, and `enum PermissionStatus { notDetermined, granted, denied, restricted }`. All are `Codable, Equatable, Sendable`.
  - **Store:**
    ```swift
    @MainActor public protocol Store: AnyObject {
        var revision: Int { get }            // increments on every change; implementations are @Observable
        func snapshot() -> StoreSnapshot      // all entities (data is small)
        func apply(_ changes: ChangeSet) throws
        func replaceAll(with snapshot: StoreSnapshot) throws   // restore
    }
    public struct StoreSnapshot: Codable, Sendable { settings, goals, firstPrinciples, systems, objectives, steps, habits, logs, weekReviews, blockRules, blocks, reminders }
    public struct ChangeSet: Sendable { public var upserts: [AnyEntity]; public var deletes: [EntityRef] }
    public enum AnyEntity: Sendable { case goal(Goal), firstPrinciple(FirstPrinciple), system(GoalSystem), objective(Objective), step(Step), habit(Habit), log(HabitLog), weekReview(WeekReview), blockRule(BlockRule), block(CalendarBlock), reminder(PlanReminder), settings(AppSettings) }
    public struct EntityRef: Sendable { public enum Kind { goal, firstPrinciple, system, objective, step, habit, log, weekReview, blockRule, block, reminder }; public let kind: Kind; public let id: UUID }
    ```
  - **Service protocols:**
    ```swift
    @MainActor public protocol CalendarServicing: AnyObject {
        var status: PermissionStatus { get }
        func requestAccess() async -> PermissionStatus
        func busyIntervals(in range: DateInterval) async -> [BusyInterval]
        func externalEvents(in range: DateInterval) async -> [ExternalEvent]
        func sync() async -> SyncReport            // §5.5 sequence; reads and writes Store
        func move(blockID: UUID, to start: Date) async throws
    }
    @MainActor public protocol NotificationServicing: AnyObject {
        var status: PermissionStatus { get }
        func requestAccess() async -> PermissionStatus
        func reschedule() async
        func pendingCount() async -> Int
    }
    @MainActor public protocol BackupServicing: AnyObject {
        var folderName: String? { get }
        func setFolder(_ url: URL) throws
        func backUpNow() throws -> URL
        func restore(from url: URL) throws
    }
    public protocol SigningInfoProviding { func expiryDate() -> Date? }
    public struct SyncReport: Sendable { created: Int, updated: Int, cancelled: Int, clashes: Int, error: String? }
    ```
  - **Engines** (stateless `enum`s with static functions):
    - `HabitEngine`: `isScheduled(_:on:)`, `mark(for:on:logs:now:)`, `logicalDay(for: Date) -> LocalDay` (applies the 04:00 rule), `weekScore(habit:week:logs:) -> HabitWeekScore`, `goalWeekScore(goal:habits:week:logs:now:settings:) -> GoalWeekScore`, `goalStreak(...)`, `habitStreak(...)`, `suggestedBottleneck(...)`, `systemStatus(...)`. All per §4.6.
    - `ScheduleEngine`: `backSchedule(objectives:goal:today:) -> [UUID: LocalDay]` plus warnings; `wouldCreateCycle(objectives:from:to:) -> Bool`; `topologicalOrder`; `materialise(rules:existing:from:days:settings:) -> [CalendarBlock]`; `detectClashes(blocks:busy:settings:)`; `suggestSlot(for:busy:blocks:settings:) -> Date?`; `feasibility(goal:snapshot:busy:now:) -> FeasibilityReport`; `mapLayout(goalID:snapshot:) -> MapLayout` (layers, nodes, edges per §4.8, no coordinates).
    - `ReminderPlanner`: `plan(snapshot:now:signingExpiry:horizonDays: 10, maxPending: 60) -> [PlannedNotification]` per §6, including the exact text templates.
    - `PlanImporter`: `decode(_ data: Data) throws(PlanImportError) -> PlanV1`; `validate(_:) -> [PlanIssue]`; `materialise(_:into: StoreSnapshot, today:settings:) -> ImportResult` (ChangeSet + review summary per §7.7, update mode per §4.4).
    - `PromptBuilder`: `intakePrompt(answers: IntakeAnswers, busy: [BusyInterval], settings:, now:) -> String` (Appendix B); `checkInPrompt(goalID:snapshot:week:) -> String` (Appendix C); `promptAddOn` constant (Appendix A).
    - `BackupCodec`: `encode(_ snapshot:) -> Data`; `decode(_:) throws -> StoreSnapshot` (Appendix D).
  - **Fakes** for previews and tests: `InMemoryStore` (an `@Observable` `Store`), `FakeCalendarService`, `FakeNotificationService` (records planned notifications), `FakeBackupService`, `FixedSigningInfo`, and `SampleData.bodyFatGoal()` matching the mockups (goal "10% body fat", 3 principles, systems Meals / Lifting M/W/F / Walk, habits Lift, Incline walk, Protein x4, Post-gym meal, sustaining "Sleep by 23:30").
- **Tests (required):** every rule in §4.4–4.7 and §6 has at least one XCTest. These include cycle rejection; the 04:00 boundary; perWeek scoring; the cap of 4 timed slots, 3 on Mondays; the 60-pending limit; template text; JSON validation errors with paths; update-mode matching; back-scheduling across a 3-level chain; slot suggestion skipping Saturday; and backup round-trip.
- **Depends on:** nothing.
- **Build order:** wave 1 (public API, fakes, SampleData), then wave 2 (engines and tests).

**M2 · Persistence (iOS)**
- **Owns:** `App/Persistence/**`.
- **Provides:**
  - `@Model` classes `GoalRecord … SettingsRecord` with the relationships and delete rules in §3.
  - `@Observable final class SwiftDataStore: Store` (with `init(inMemory: Bool = false)`), mapping records to and from CoreKit structs. `revision` increments after every save.
  - `final class FileBackupService: BackupServicing`: security-scoped bookmark, naming and pruning per §9.3, uses `BackupCodec`.
  - `struct ProvisioningSigningInfo: SigningInfoProviding` per §9.3.
- **Depends on:** M1.
- **Build order:** wave 2.

**M3 · Design System (iOS)**
- **Owns:** `App/DesignSystem/**`.
- **Provides:** tokens (§8.1–8.3), `Haptics` helpers (§8.4), the components in §8.5 with SwiftUI previews, and the motion constants (§8.6). No business logic: components take plain values.
- **Depends on:** M1 (only for `Mark`).
- **Build order:** wave 2 (it can start in wave 1).

**M4 · Habits, Today and Week (iOS)**
- **Owns:** `App/Features/Habits/**`, `App/Features/Today/**`, `App/Features/Week/**`.
- **Provides these views (exact names and initialisers):** `HabitsTabView()`, `HabitEditorView(habitID: UUID?)`, `HabitMarkSheet(habitID: UUID, day: LocalDay)`, `TodayAccessoryView()`, `TodaySheet()`, `WeekTabView()`.
- **Uses:** `AppServices` from the environment (store, notifications, backup), `Router`, CoreKit engines, M3 components.
- **After every mark:** `store.apply`, then `await notifications.reschedule()`.
- **Depends on:** M1, M3, `App/Shared`.
- **Build order:** wave 2.

**M5 · Goals (iOS)**
- **Owns:** `App/Features/Goals/**`.
- **Provides these views:** `GoalsDashboardView()`, `GoalDetailView(goalID: UUID)`, `GoalMapView(goalID: UUID)`, `GoalOutlineView(goalID: UUID)`, `IntakeFlowView()`, `ImportPlanView(goalID: UUID?)`, and the editor sheets for goal, principle, system, block rule, reminder, milestone and step. The habit editor comes from M4 through `Router` (`.push(.habitEditor(id))`).
- **Handles:** clipboard, opening Claude, `.fileImporter`.
- **Depends on:** M1, M3, `App/Shared`.
- **Build order:** wave 2.

**M6 · Calendar (iOS)**
- **Owns:** `App/Features/Calendar/**`, `App/Services/Calendar/**`.
- **Provides:**
  - `final class EventKitCalendarService: CalendarServicing` (`EKEventStore`, `requestFullAccessToEvents`, Goals calendar creation, the §5.5 sync sequence, observing `.EKEventStoreChanged`). It calls `ScheduleEngine` for materialising, clashes and suggestions.
  - Views: `CalendarTabView()`, `BlockSheet(blockID: UUID)`, `ConflictSheet(blockID: UUID)`, `NewBlockSheet(start: Date)`.
- **Depends on:** M1, M3, `App/Shared`.
- **Build order:** wave 2.

**M7 · Shell, Reminders and Build (iOS + CI)**
- **Owns:** `project.yml`, `.github/**`, `README.md`, `App/Shared/**`, `App/Shell/**`, `App/Resources/**`, `App/Services/Notifications/**`.
- **Wave 1 contract files in `App/Shared/`** (written first so wave 2 can code against them):
  ```swift
  enum AppTab: Hashable { case goals, calendar, habits, week }
  enum PushRoute: Hashable { case goalDetail(UUID), habitEditor(UUID?), settings }
  enum SheetRoute: Identifiable { case markHabit(UUID, LocalDay), today, conflict(UUID), block(UUID), newBlock(Date), newGoal, importPlan(UUID?) }
  @Observable @MainActor final class Router {
      var tab: AppTab = .goals
      var goalsPath: [PushRoute] = []; var habitsPath: [PushRoute] = []
      var sheet: SheetRoute?
      var toast: String?
      func open(_ link: DeepLink)          // maps links per §6.5
      func push(_ route: PushRoute)        // onto the current tab's path
  }
  @Observable @MainActor final class AppServices {
      let store: any Store; let calendar: any CalendarServicing; let notifications: any NotificationServicing
      let backup: any BackupServicing; let signing: any SigningInfoProviding
      static func live() -> AppServices    // wires M2/M6/M7 implementations (compiles at integration)
      static func preview() -> AppServices // CoreKit fakes + SampleData
  }
  ```
- **Provides:**
  - `LockInApp` (`@main`): builds `AppServices.live()`, injects `.environment(services)` and `.environment(router)`, applies `.tint(.cobalt)` and `.preferredColorScheme(.dark)`, handles `.onOpenURL` (DeepLinks and `.json` files) and scene-phase triggers (§5.5, §6.3).
  - `RootTabView`: TabView, the Today accessory, and presenting `Router.sheet` by switching to the feature views named above.
  - `OnboardingView`, `SettingsView`.
  - `final class LocalNotificationService: NotificationServicing` (runs `ReminderPlanner` on `store.snapshot()` and implements §6.3, with a `UNUserNotificationCenterDelegate` that routes taps to `Router.open`).
  - Info.plist (§9.2–9.3: `UIUserInterfaceStyle`, `NSCalendarsFullAccessUsageDescription`, `CFBundleURLTypes` for `lockin`, `LSApplicationQueriesSchemes` = [`claude`], `CFBundleDocumentTypes` for `public.json` with role Viewer and rank Alternate). Assets: app icon placeholder (cobalt glow on `#050608`).
  - `project.yml`: one iOS app target "LockIn", deployment target 26.0, Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` [VERIFY the setting name in Xcode 26], local package dependency `Packages/CoreKit`, sources `App/`.
  - The CI workflow (§9.4).
- **Depends on:** M1 in wave 1; everything at integration.
- **Build order:** wave 1 (contracts, project, CI), wave 2 (shell, notifications, settings), wave 3 (integration).

### 10.3 Build order
1. **Wave 1:** M1 public API, fakes and SampleData; M7 contracts, `project.yml` and CI. M3 may start. Exit: `swift test` passes on Linux with stub tests, and `App/Shared` is committed.
2. **Wave 2 (parallel):** M1 engines and tests, M2, M3, M4, M5, M6, M7 shell and notifications. Each feature agent first commits its public view types as compiling stubs, then fills them in. Agents compile CoreKit on Linux. App code is compiled by CI only, because there is no Mac.
3. **Wave 3 (integration, owned by M7):** run CI and read failures with `gh run view --log-failed`. Send each error to the module that owns the failing file; owners fix only their own files. Repeat until `ios-build` is green. Then run the §2.1 acceptance checklist on the phone (the user does this).

---

## 11. Open decisions and assumptions

Answers recorded 2026-10-20 from the first green CI build (GitHub `macos-26` runner, Xcode 26.6 build 17F113, Swift 6.3.3, iPhoneOS 26.5 SDK). "Device" means only the phone can settle it.

| # | Item | Recommendation | Answer |
|---|---|---|---|
| O1 | [OPEN] App name and bundle ID | "Lock in", `com.youssoufdiallo.lockin`. Never change the bundle ID after the first install. | Decided: built as "Lock in" (`CFBundleDisplayName`), bundle ID `com.youssoufdiallo.lockin`. |
| O2 | [OPEN] Today strip as a tab bar accessory | Use `.tabViewBottomAccessory`, falling back to the top row of the Goals list. | Decided: `.tabViewBottomAccessory` compiles (see V1), so the fallback row is not used. |
| O3 | [OPEN] Default best hours | As in §3.12; the user edits them in onboarding. | Decided: defaults as in §3.12, editable in onboarding and Settings. |
| O4 | [OPEN] Public vs private GitHub repo | Public (no personal data in the repo) for free CI minutes. | Decided: public repo `GodlyGamer/lockin`. |
| V1 | [VERIFY] Liquid Glass API names (`.glassProminent` inside a toolbar, `ToolbarSpacer`, `.tabViewBottomAccessory`) on the SDK the runner has | Build as written; replace with the SDK's names if the compile fails. | **Settled by the compiler.** `.tabViewBottomAccessory`, `ToolbarSpacer(.fixed, placement:)`, `.buttonStyle(.glassProminent)`, `.buttonStyle(.glass)`, `GlassEffectContainer` and `.glassEffectID(_:in:)` all compile unchanged against the iOS 26.5 SDK. **Device:** whether the New goal button *looks* prominent inside the toolbar. |
| V2 | [VERIFY] Whether Xcode 27 is on the `macos-26` runner | Not needed: target iOS 26.0 and use no iOS 27-only API. | **Settled by CI.** The `macos-26` image has Xcode 26.0 through 26.6 (default 26.6) and no Xcode 27. CI selects the newest Xcode 26; the app targets iOS 26.0 and uses no iOS 27 API. |
| V3 | [VERIFY] Claude app URL scheme | Try `claude://`; the clipboard plus toast is the fallback either way. | **Device.** `claude` is listed in `LSApplicationQueriesSchemes`; the clipboard + toast fallback ships either way. |
| V4 | [VERIFY] Reading `ExpirationDate` from `embedded.mobileprovision` on a Sideloadly-signed build | Show "Unknown" and skip the warning if it fails. | **Device.** Reader implemented as specified (M2 `ProvisioningSigningInfo`); it returns nil and Settings shows "Unknown" on any failure. |
| V5 | [VERIFY] Sideloadly's bundle-ID option keeps the ID unchanged | Keep it off; confirm the installed app's container survives a re-sign (data still there). | **Device.** |
| V6 | [VERIFY] Scheduled notifications fire while the app is expired | If they do, the re-sign notification still reaches the user; if not, the banner is the warning. | **Device.** |
| V7 | [VERIFY] Writing backups to an iCloud Drive folder without the iCloud capability | Fall back to "On My iPhone" if it fails. | **Device.** Backups use a security-scoped bookmark from the folder picker and plain atomic writes; restore reads through `NSFileCoordinator`. |
| V8 | [VERIFY] Free Apple ID app-ID and active-app limits | Single target, no extensions. | **Device / Apple account.** Not stated in Apple's developer docs; the app stays a single target with no extensions. |
| V9 | [VERIFY] Hidden calendars still sync through EventKit | Expected yes; the onboarding tip depends on it. | **Device.** |
| V10 | [VERIFY] `SWIFT_DEFAULT_ACTOR_ISOLATION` build setting name | If absent, mark view models `@MainActor` explicitly. | **Settled by the compiler.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is the right name: Xcode 26.6 passes `-default-isolation=MainActor` to every app compile. `SWIFT_APPROACHABLE_CONCURRENCY = YES` adds `InferIsolatedConformances` and `NonisolatedNonsendingByDefault`. |
| V11 | [VERIFY] Free macOS CI minutes for private repos | See O4. | **Settled by GitHub's billing docs.** macOS jobs use private-repo minutes at 10× the Linux rate; standard runners are free for public repos. Moot, as the repo is public (O4). |
| A1 | Assumption: one user, one device, one time zone (Europe/London); week starts Monday | |  |
| A2 | Assumption: the user's goal-system prompt in Claude is updated with Appendix A so plans end in valid JSON | |  |
| A3 | Assumption: the uni timetable is a subscribed calendar in Apple Calendar (read-only) | |  |

---

## Appendix A — Prompt add-on for the user's goal-system prompt, and Plan JSON schema v1

Paste this at the end of the goal-system prompt's instructions in Claude (the same text is available in Settings → Claude → "Copy prompt add-on"). The outer fence here is `~~~` because the text itself contains a ```json fence:

~~~
When the plan is final, end your reply with exactly one ```json code block that follows "Lock in plan schema v1" below, with nothing after it. Use the times and busy blocks I gave you. Never put goal work on Saturday unless it's physical. Every habit needs a bad-day version. If my message includes "goalId", copy it into goal.id and keep every existing key the same so the app updates the goal rather than creating a new one.

Lock in plan schema v1:
{
  "schemaVersion": 1,
  "goal": { "id": "UUID or null", "key": "g", "title": "", "outcome": "", "deadline": "YYYY-MM-DD", "bufferDays": 7,
            "result": { "name": "", "unit": "", "start": 0, "target": 0 } },
  "firstPrinciples": [ { "key": "fp1", "title": "", "why": "" } ],
  "systems": [ { "key": "s1", "firstPrinciple": "fp1 or null", "kind": "principle | sustaining", "title": "", "location": "or null" } ],
  "objectives": [ { "key": "o1", "title": "", "estimatedDays": 14, "dependsOn": ["o0"], "systems": ["s1"], "deadline": "YYYY-MM-DD or null" } ],
  "steps": [ { "key": "st1", "objective": "o1", "title": "", "estimatedMinutes": 30, "deadline": "YYYY-MM-DD or null" } ],
  "habits": [ { "key": "h1", "system": "s1", "title": "", "badDayTitle": "", "kind": "check | count", "target": 1, "badDayTarget": 1, "unit": "or null",
                "frequency": { "type": "daily | weekdays | perWeek", "weekdays": [1,3,5], "timesPerWeek": 5, "preferredWeekdays": [1,2,4] },
                "setPointPerWeek": 3, "reminderTime": "HH:mm or null", "durationMinutes": 30, "isPhysical": false, "priority": 3 } ],
  "blocks": [ { "key": "b1", "system": "s1", "title": "", "durationMinutes": 60, "weekdays": [7], "date": "YYYY-MM-DD or null", "startTime": "HH:mm",
                "windowStart": "HH:mm", "windowEnd": "HH:mm", "isPhysical": false, "nudge": false } ],
  "reminders": [ { "key": "r1", "system": "s1 or null", "title": "", "body": "", "date": "YYYY-MM-DD or null", "weekdays": [], "time": "HH:mm", "priority": 3 } ]
}
Rules: weekdays are 1=Mon … 7=Sun. Exactly one system has kind "sustaining" (firstPrinciple null). Keys are unique per list. dependsOn must not form a loop. For a "count" habit, badDayTarget < target. A block uses either weekdays (repeating) or date (one-off).
~~~

**Decoding rules (PlanImporter):**
- Unknown fields are ignored.
- Missing optional fields use these defaults: `bufferDays` 7, `priority` 3, `durationMinutes` 15, `setPointPerWeek` = scheduled count, `nudge` false, `isPhysical` false, `location` null.
- For `frequency.type`: `daily` ignores the arrays; `weekdays` requires `weekdays`; `perWeek` requires `timesPerWeek` (1–7) and uses `preferredWeekdays` (default `[]`).
- `kind = check` forces `target = badDayTarget = 1`.
- The importer accepts the JSON either alone or inside a ```json fence anywhere in the pasted text. It takes the last fenced block.

## Appendix B — Intake prompt template (`PromptBuilder.intakePrompt`)

```
New goal for my goal system. Use my method: work backwards to first principles, one system per principle, one sustaining system, and a DAG of milestones with deadlines. Grill me on anything you still need first, then give the plan and finish with the Lock in plan JSON (schema v1).

Goal: {q1}
Measured by: {resultName} ({unit}). Now: {q3}. Target: {q4}. Deadline: {deadline YYYY-MM-DD}.
Tried before: {q6 or "—"}
Resources: {q7}
Hard limits: {q8 or "—"}
Why it matters: {q9 or "—"}
Hours a week: {q10}
Best times: {chips joined ", "}
Best places: {chips joined ", "}
Saturdays off for goal work: {yes/no} (physical activity still fine)
What usually makes me stop: {chips}
Smallest bad-day version: {q15 or "—"}
Today: {EEE d MMM yyyy}
Busy times, next 14 days (06:00–24:00, titles hidden):
{one line per day: "Mon 20 Oct: 09:00–11:00, 13:00–15:00" or "Mon 20 Oct: free"}
```

## Appendix C — Check-in prompt template (`PromptBuilder.checkInPrompt`)

```
Weekly check-in for goal "{title}" (goalId: {uuid}). Week {d MMM}–{d MMM}.
Result: {resultName} {value}{unit} (target {target}{unit}, start {start}{unit}).
Scorecard (D = done, B = bad-day version, M = missed, - = not scheduled):
{habit}: {7 marks Mon..Sun} — {done}/{setPoint}{ — FLAG: {bad} of {done} were B}
...
On target: {onTarget} of {total}. Streak: {n} weeks. Bottleneck I picked: {habit}.
Note: {note or "—"}
Current plan JSON (keep keys the same):
{the goal's current plan as schema v1 JSON, rebuilt from the store}
Redesign anything flagged or below set point, then finish with the full updated plan JSON (schema v1, same goalId and keys).
```

## Appendix D — Backup file format

```
{ "format": "lockin-backup", "schemaVersion": 1, "exportedAt": "ISO-8601", "appVersion": "1.0 (1)",
  "data": <StoreSnapshot encoded with JSONEncoder: dates ISO-8601, LocalDay as "YYYY-MM-DD", keys sorted, pretty printed> }
```
Restore rejects files whose `format` isn't `lockin-backup` or whose `schemaVersion` is newer than the app's, showing "This backup is from a newer version of the app."
