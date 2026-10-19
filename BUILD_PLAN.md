# BUILD_PLAN.md — Lock in

DESIGN.md is the single source of truth. This file says **who builds what, in which order, against which interfaces**. Nothing here adds a feature beyond the MVP table in DESIGN.md §2.1. If this file and DESIGN.md disagree, DESIGN.md wins, except for the contract clarifications in §2 below (they fill gaps DESIGN.md leaves open and are frozen in code in wave 1).

Ground rules for every agent:
- You own exactly the paths listed in your brief. Do not create, edit, move or delete anything else. Not even a typo fix.
- Nobody changes CoreKit's **public** API (`Packages/CoreKit/Sources/CoreKit/**` public declarations) or anything in `App/Shared/**` except the integrator (the main session). If you need a change, send a message to `main` with the exact declaration you need and why, then carry on with other work. When the integrator says it has landed, run `git merge main` in your worktree.
- There is no Mac. CoreKit compiles and tests on Linux (WSL: `wsl.exe -d Ubuntu -- bash -lc 'swift test --package-path /mnt/d/<your worktree>/Packages/CoreKit --scratch-path /root/.build-<module>'`). iOS code is compiled **only** by the GitHub Actions `macos-26` job, so write it carefully: Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, iOS 26.0 deployment target, iOS 26 SDK APIs only (no iOS 27-only API).
- Commit early and often on your worktree branch. Commit messages: `M<n>: <what>`.
- iOS views read services with `@Environment(AppServices.self) private var services` and `@Environment(Router.self) private var router`. Views re-render on data changes by reading `services.store.revision` in `body` (the store is `@Observable`), then derive what they need from `services.store.snapshot()`.
- Every view gets a `#Preview` that uses `AppServices.preview()` and `Router()`.
- Never use `Material`, `.blur` as glass, custom tab bars, `.toolbarBackground` colours or `UITabBarAppearance` (DESIGN.md §8.7 "Banned").

---

## 1. Waves (DESIGN.md §10.3)

### Wave 1 — contracts (integrator, sequential)
1. CoreKit public API: every domain type, `Store` and friends, service protocols, engine **signatures** with stub bodies, `BackupCodec`, fakes (`InMemoryStore`, `FakeCalendarService`, `FakeNotificationService`, `FakeBackupService`, `FixedSigningInfo`) and `SampleData.bodyFatGoal()`.
2. Stub tests so `swift test --package-path Packages/CoreKit` passes on Linux.
3. M7's wave 1 files: `App/Shared/*` (AppTab, PushRoute, SheetRoute, Router, AppServices), `project.yml`, `.github/workflows/build.yml`, `App/Resources/Info.plist`, `App/Resources/Assets.xcassets`.
4. Push to the public GitHub repo. **Exit:** `core-tests` green. (`ios-build` is expected to fail until wave 3, because `AppServices.live()` names wave 2 types.)

### Wave 2 — modules in parallel (one Sonnet agent per module, each in its own git worktree)
M1 engines + tests, M2, M3, M4, M5, M6, M7 shell + notifications. Each feature agent **first commits its public view types as stubs** with the exact initialisers below (body `Text("…")`), then fills them in. M1 is the only one that can compile; everyone else reviews their own code carefully against the iOS 26 SDK.

### Wave 3 — integration (integrator)
1. Merge every module branch into `main` (ownership is disjoint, so merges should be clean), push.
2. `gh run watch`; on failure `gh run view --log-failed`.
3. Route each compiler error to the agent that owns the file (by path, using the ownership table). Owners fix only their own files and commit; integrator merges and pushes again.
4. Repeat until `ios-build` is green and `LockIn.ipa` is uploaded.
5. Record every [VERIFY] answer the compiler or Apple's docs settle in DESIGN.md §11. Device-only items stay for the user.

---

## 2. Contract clarifications (frozen in wave 1)

These are small additions DESIGN.md needs to be buildable. They are in the code; agents use them as written.

| Where | Addition | Why |
|---|---|---|
| `Habit` | `sortIndex: Int` | §4.6 bottleneck tie-break uses habit `sortIndex`, but §3.6 omits it. |
| `BusyInterval` | `eventID: String?` | §5.4 clash checks compare against `ignoredClashEventIDs`. |
| `ExternalEvent` | `isFree: Bool` | §5.2 excludes `.free` events from busy intervals. |
| `Store` | `var loadError: String? { get }` (default `nil`) | §7.2 "Your data couldn't load" state. |
| `StoreSnapshot.applying(_:)` | Applies a `ChangeSet` with §3 delete rules (cascade / nullify) | So `InMemoryStore` and `SwiftDataStore` agree. A `ChangeSet` lists only the root deletes. |
| `ScheduleEngine.materialise` | extra trailing `systems: [GoalSystem] = []` | To fill `CalendarBlock.goalID` from the rule's system. |
| `ScheduleEngine.suggestSlot` | extra `rule: BlockRule?` | The search window comes from the rule (§5.4). |
| `ScheduleEngine.detectClashes` | extra `now: Date` | Only future blocks clash. Busy intervals are passed raw; the engine applies `travelBufferMinutes`. |
| `PromptBuilder.intakePrompt` | `busy: [BusyInterval]?` | `nil` → "Busy times: not available (calendar access off)". |
| `PlanImporter.materialise` | runs back-scheduling (§4.5) itself | Callers just `apply` the result, then `await calendar.sync()`. |
| `CalendarServicing.sync()` | always ends with `await notifications.reschedule()`, **even when calendar access is denied** | §5.5 step 6; callers never reschedule after a sync themselves. |
| `Router` | `pendingImportURL: URL?` | `.onOpenURL` for a `.json` file sets it and opens `.importPlan(nil)`; `ImportPlanView` consumes it. |
| CoreKit imports | `Foundation` **and `Observation`** | `InMemoryStore` must be `@Observable` (§10.2); Observation ships with the Linux toolchain. |
| Time zone | All CoreKit date maths uses `Calendar.lockIn` (Gregorian, Europe/London, Monday first) | A1; makes Linux tests deterministic. |

Concrete service initialisers (used by `AppServices.live()`, so they are part of the contract):

```swift
SwiftDataStore(inMemory: Bool = false)                                       // M2
ProvisioningSigningInfo()                                                     // M2
FileBackupService(store: any Store)                                           // M2
LocalNotificationService(store: any Store, signing: any SigningInfoProviding) // M7
  var onOpenLink: ((DeepLink) -> Void)?   // set by LockInApp; called on notification tap
EventKitCalendarService(store: any Store, notifications: any NotificationServicing) // M6
```

---

## 3. Ownership table (DESIGN.md §10.1)

```
/project.yml                                   M7 (wave 1: integrator)
/.github/workflows/build.yml                   M7 (wave 1: integrator)
/README.md                                     M7
/Packages/CoreKit/Package.swift                M1 (public API: integrator)
/Packages/CoreKit/Sources/CoreKit/**           M1 (public API: integrator)
/Packages/CoreKit/Tests/CoreKitTests/**        M1
/App/Shared/**                                 integrator only
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

---

## 4. Module briefs

Each brief is self-contained. Read DESIGN.md sections named in your brief in full before writing code.

### M1 · CoreKit engines and tests

- **Owns:** `Packages/CoreKit/**`. Public signatures are frozen; you write bodies, internal helpers and tests.
- **Read:** DESIGN.md §3, §4.4–4.7, §5.3–5.4, §6, Appendices A–D.
- **Rules:** import only `Foundation` (and `Observation`, already used by the fakes). No SwiftUI, SwiftData, EventKit, UserNotifications, UIKit. All date maths through `Calendar.lockIn` / `LocalDay`.
- **Provides (signatures already in the code; implement them):**
  - `HabitEngine`: `isScheduled(_:on:)`, `isDue(_:on:logs:)`, `mark(for:on:logs:now:)`, `derivedMark(count:habit:)`, `logicalDay(for:)` (04:00 rule), `scheduledPerWeek(_:)`, `weekScore(habit:week:logs:) -> HabitWeekScore`, `goalWeekScore(goal:habits:week:logs:now:settings:) -> GoalWeekScore`, `goalStreak(...)`, `habitStreak(...)`, `suggestedBottleneck(...)`, `systemStatus(...)`. All per §4.6.
  - `ScheduleEngine`: `backSchedule(objectives:goal:today:) -> BackScheduleResult`, `wouldCreateCycle(objectives:from:to:)`, `topologicalOrder(_:)`, `materialise(rules:existing:from:days:settings:systems:)`, `detectClashes(blocks:busy:settings:now:)`, `suggestSlot(for:rule:busy:blocks:settings:)`, `feasibility(goal:snapshot:busy:now:) -> FeasibilityReport`, `mapLayout(goalID:snapshot:) -> MapLayout`.
  - `ReminderPlanner.plan(snapshot:now:signingExpiry:horizonDays:maxPending:) -> [PlannedNotification]` per §6 with the exact §6.4 templates and §6.3 identifiers.
  - `PlanImporter`: `extractJSON(from:)`, `decode(_:) throws(PlanImportError) -> PlanV1`, `validate(_:) -> [PlanIssue]`, `materialise(_:into:today:settings:) -> ImportResult` (includes update mode §4.4 and back-scheduling).
  - `PlanV1.init(goalID:snapshot:)` + `jsonString()` (rebuilds a goal as schema v1 for the check-in prompt).
  - `PromptBuilder`: `intakePrompt(answers:busy:settings:now:)`, `checkInPrompt(goalID:snapshot:week:)`, `promptAddOn`.
  - `BackupCodec` is already implemented; keep its round-trip test green.
- **May use:** nothing outside the package.
- **Required tests (XCTest, `Tests/CoreKitTests/`; one file per engine):** every rule in §4.4–4.7 and §6 has at least one test, including:
  - cycle rejection (`wouldCreateCycle`, `validate` on a `dependsOn` loop);
  - the 04:00 boundary (`logicalDay` at 01:30 Tue → Mon; 04:00 → same day);
  - perWeek scoring (cap at n; marks on any day);
  - `hit`, `badDayFlag` (3 done, 2 B → flagged), goal streak only after a week where every habit hit;
  - cap of 4 timed slots, 3 on the check-in day; priority then time ordering; marking D before reminder drops that day's habit nudge;
  - the 60-pending limit (+ re-sign on top, ≤ 61);
  - template text for all seven kinds (including "Leave out 0 blocks", "+N more", horizon warning suffix);
  - JSON validation errors with paths (e.g. `habits[2].frequency.weekdays: 8 is not 1–7`), first 5 only; fenced JSON extraction takes the last block;
  - update-mode matching by `planKey` (update / insert / archive habit / delete rule + future blocks; logs untouched);
  - back-scheduling across a 3-level chain, override respected, "starts N days too late";
  - slot suggestion skipping Saturday (non-physical) and never overlapping blocks;
  - feasibility warning threshold (0.8);
  - Saturday move ("Moved off Saturday: Meal prep → Sun 17:00");
  - intake prompt has no event titles and the "not available" line when `busy == nil`;
  - backup round-trip and newer-schemaVersion rejection.
- **Acceptance checks this module makes true (logic side):** F1.1–1.2, F2.2–2.3, F3.1–3.3, F4.2–4.4, F6.1 defaults (`IntakeAnswers.defaults`), F6.2, F7.1–7.2, F8.2–8.3, F9.4 (suggestion), F10.3–10.4, F11.2 (codec), F12.1 (planner side).
- **Done when:** `swift test --package-path Packages/CoreKit` passes on Linux with all of the above.

### M2 · Persistence

- **Owns:** `App/Persistence/**`.
- **Read:** DESIGN.md §3, §9.3, Appendix D.
- **Provides:**
  - `@Model` classes `GoalRecord, FirstPrincipleRecord, GoalSystemRecord, ObjectiveRecord, StepRecord, HabitRecord, HabitLogRecord, WeekReviewRecord, BlockRuleRecord, CalendarBlockRecord, PlanReminderRecord, SettingsRecord` with the relationships and delete rules in §3. Enums and arrays stored as raw values / Codable data so SwiftData never needs to understand CoreKit enums with associated values (store `Frequency` as JSON `Data`, `LocalDay` as its `String`).
  - `@Observable final class SwiftDataStore: Store` with `init(inMemory: Bool = false)`. Store file `Application Support/LockIn.store`. `revision` increments after every successful save. `snapshot()` maps every record to CoreKit structs. `apply(_:)` upserts by `id`, deletes by `EntityRef` (cascades come from the delete rules; must match `StoreSnapshot.applying` semantics). `replaceAll(with:)` deletes everything and inserts the snapshot. If the container fails to load, fall back to an in-memory container and set `loadError`.
  - `final class FileBackupService: BackupServicing` with `init(store: any Store)`: security-scoped bookmark stored in `AppSettings.backupFolderBookmark` (through `store.apply`), `folderName`, `backUpNow()` writes `lockin-backup-YYYY-MM-DD.json` and `lockin-backup-latest.json` with `BackupCodec.encode`, prunes dated files older than 8 weeks (only that name pattern), updates `lastBackupAt`. `restore(from:)` uses `BackupCodec.decode` then `store.replaceAll`. (Sync and reschedule after restore are the caller's job: Settings.)
  - `struct ProvisioningSigningInfo: SigningInfoProviding` with `init()` per §9.3 (bytes between `<?xml` and `</plist>`, `PropertyListSerialization`, `ExpirationDate`; nil on any failure).
- **May use:** CoreKit (`Store`, `StoreSnapshot`, `ChangeSet`, `AnyEntity`, `EntityRef`, all domain structs, `BackupCodec`, `BackupServicing`, `SigningInfoProviding`).
- **Acceptance checks:** F1.3 (archived habits keep logs), F11.1–11.2, F12.2 (expiry date source).

### M3 · Design System

- **Owns:** `App/DesignSystem/**`.
- **Read:** DESIGN.md §7.4, §7.10 (dots), §8 in full.
- **Provides:**
  - `DesignSystem/Tokens.swift`: `Color` extensions for every §8.1 token (`.canvas, .cobalt, .cobaltText, .ember, .emberText, .emberEdge, .textPrimary, .textSecondary, .textTertiary, .markB, .markMStroke, .notScheduled, .blockFill, .eventFill, .tileTop, .tileBottom`…), gradients as static members (`Gradient`/`RadialGradient` factories: `canvasGlow`, `horizonGlow`, `cobaltFill`, `emberFill`, `tileGradient`), and `Color(hex:)`.
  - `Typography.swift`: `Font` / view modifiers for every §8.2 token (`.screenTitle`, `.tileTitle`, …), Dynamic Type based only.
  - `Spacing.swift`: §8.3 constants (`Spacing.s4…s32`, `Radius.tile = 28` …).
  - `Haptics.swift`: §8.4 events as a `enum HapticEvent` + a `.haptic(_:trigger:)` modifier over `.sensoryFeedback`.
  - `Motion.swift`: §8.6 constants that respect Reduce Motion.
  - `Components/`: `NightCanvas`, `GrainOverlay` (internal), `GoalTile`, `ProgressGauge` + `GaugeModel`, `MarkDot`, `HabitRow`, `TitleText`, `FlagBox`, `PermissionBanner`, `MapNode`, `.toast(text:)` with the exact §8.5 APIs, each with `#Preview`. VoiceOver labels per §8.8.
  - `GaugeModel.State` is `.onTrack / .behind / .neutral`; `MapNode` state `.onTrack / .behind / .done / .neutral` (call it `MapNodeState`).
- **May use:** CoreKit `Mark` only. No business logic, no `AppServices`.
- **Acceptance checks:** F15.1–15.2 (glass only where §8.7 allows; NightCanvas gives the tab bar light to refract), F2.1 dot colours.

### M4 · Habits, Today and Week

- **Owns:** `App/Features/Habits/**`, `App/Features/Today/**`, `App/Features/Week/**`.
- **Read:** DESIGN.md §3.6–3.8, §4.6, §7.3, §7.4, §7.9, §7.10, §8, Appendix C.
- **Provides (exact names and initialisers):** `HabitsTabView()`, `HabitEditorView(habitID: UUID?)`, `HabitMarkSheet(habitID: UUID, day: LocalDay)`, `TodayAccessoryView()`, `TodaySheet()`, `WeekTabView()`.
- **May use:** `AppServices` (store, notifications, backup, calendar for clash count), `Router` (`.sheet = .markHabit(...)`, `.push(.habitEditor(id))`, `.toast`), CoreKit engines (`HabitEngine`, `PromptBuilder.checkInPrompt`), M3 components.
- **Rules:** after every mark: `try services.store.apply(...)`, then `await services.notifications.reschedule()`. Mark day defaults to `HabitEngine.logicalDay(for: .now)`. Week "Send to Claude": copy prompt, try `claude://`, else toast "Copied. Open Claude and paste it into your goal-system project.", then `router.sheet = .importPlan(goalID)`. "Finish": save WeekReviews with `finishedAt`, `backUpNow()` (toast "Backup skipped. Choose a folder in Settings." if no folder), reschedule, toast "Week saved".
- **Acceptance checks:** F1.1–1.3 (UI side), F2.1–2.3, F3.1–3.3 display, F5.2, F10.1–10.3, F11.1 (Finish triggers backup).

### M5 · Goals

- **Owns:** `App/Features/Goals/**`.
- **Read:** DESIGN.md §3.1–3.5, §4 in full, §7.2, §7.5–7.7, §8.
- **Provides:** `GoalsDashboardView()`, `GoalDetailView(goalID: UUID)`, `GoalMapView(goalID: UUID)`, `GoalOutlineView(goalID: UUID)`, `IntakeFlowView()`, `ImportPlanView(goalID: UUID?)`, editor sheets for goal, principle, system, block rule, reminder, milestone, step (names: `GoalEditorSheet`, `PrincipleEditorSheet`, `SystemEditorSheet`, `BlockRuleEditorSheet`, `ReminderEditorSheet`, `MilestoneEditorSheet`, `StepEditorSheet`, `DependencyPicker`). The habit editor comes from M4 via `router.push(.habitEditor(id))`.
- **May use:** `AppServices` (store, calendar, notifications, signing), `Router` (`.goalsPath`, `.sheet`, `.toast`, `.pendingImportURL`, `.tab`), CoreKit (`HabitEngine`, `ScheduleEngine`, `PlanImporter`, `PromptBuilder`, `IntakeAnswers`), M3 components.
- **Rules:** clipboard via `UIPasteboard.general`; open Claude via `UIApplication.shared.open(URL(string: "claude://")!)` with the toast fallback; `.fileImporter(allowedContentTypes: [.json])`. After "Add to app": `try store.apply(result.changes)` then `await services.calendar.sync()` (which reschedules). Intake draft kept in `@SceneStorage` as JSON (`IntakeAnswers` is Codable). Dashboard shows the Monday check-in banner and the re-sign banner (`services.signing.expiryDate()` within 48 h). Toolbar: Settings (`gearshape`, `router.push(.settings)`), `ToolbarSpacer(.fixed)`, New goal (`plus`, `.buttonStyle(.glassProminent)`, `router.sheet = .newGoal`).
- **Acceptance checks:** F5.1 (dashboard content), F5.3, F6.1–6.3, F7.1–7.4, F8.1–8.3, F12.1 (banner).

### M6 · Calendar

- **Owns:** `App/Features/Calendar/**`, `App/Services/Calendar/**`.
- **Read:** DESIGN.md §3.10, §5 in full, §7.8, §8.
- **Provides:**
  - `final class EventKitCalendarService: CalendarServicing`, `init(store: any Store, notifications: any NotificationServicing)`. `requestFullAccessToEvents`, Goals calendar creation (§5.3), observes `.EKEventStoreChanged` (calls `sync()`), the §5.5 sequence using `ScheduleEngine.materialise / detectClashes / suggestSlot`, event fields per §5.2, finishes within 2 s for 200 events, always ends with `await notifications.reschedule()`. `busyIntervals` excludes the Goals calendar, all-day and `.free` events and fills `eventID`. `move(blockID:to:)` updates the block, clears clash state and pushes the event.
  - Views: `CalendarTabView()`, `BlockSheet(blockID: UUID)`, `ConflictSheet(blockID: UUID)`, `NewBlockSheet(start: Date)`.
- **May use:** `AppServices`, `Router` (`.sheet = .block/.conflict/.newBlock/.markHabit`, `.toast`), CoreKit (`ScheduleEngine`, `HabitEngine`), M3 components.
- **Acceptance checks:** F9.1–9.4, F7.4 (blocks written to Goals calendar on sync).

### M7 · Shell, Reminders and Build

- **Owns:** `project.yml`, `.github/**`, `README.md`, `App/Shell/**`, `App/Resources/**`, `App/Services/Notifications/**`. (`App/Shared/**` is integrator-only; ask for changes.)
- **Read:** DESIGN.md §6, §7 (global, 7.1, 7.11), §8.7, §9 in full, §10.
- **Provides:**
  - `LockInApp` (`@main`, `App/Shell/LockInApp.swift`): builds `AppServices.live()` and a `Router`, injects both with `.environment`, `.tint(.cobalt)`, `.preferredColorScheme(.dark)`, `.onOpenURL` (DeepLink → `router.open`; `.json` file URL → `router.pendingImportURL = url; router.sheet = .importPlan(nil)`), scene-phase `.active` → `await services.calendar.sync()` (which reschedules). Sets `notifications.onOpenLink = { router.open($0) }`.
  - `RootTabView`: system `TabView(selection:)` with `Tab("Goals", systemImage: "target", value: AppTab.goals)`, Calendar `calendar`, Habits `checklist`, Week `chart.bar`; each tab its own `NavigationStack` (goals and habits bound to `router.goalsPath / habitsPath` with `.navigationDestination(for: PushRoute.self)` mapping to `GoalDetailView`, `HabitEditorView`, `SettingsView`); `.tabViewBottomAccessory { TodayAccessoryView() }`; one `.sheet(item: $router.sheet)` switching over `SheetRoute` to the feature views; `.fullScreenCover` for onboarding while `!settings.onboardingDone`.
  - `OnboardingView` (§7.1) and `SettingsView` (§7.11, every `AppSettings` field editable; each change `store.apply` + `await notifications.reschedule()`; restore then `await calendar.sync()`).
  - `final class LocalNotificationService: NSObject, NotificationServicing, UNUserNotificationCenterDelegate` (`init(store:signing:)`, `onOpenLink`): `reschedule()` = `ReminderPlanner.plan(snapshot:now:signingExpiry:)` → `removeAllPendingNotificationRequests()` → add each with `UNCalendarNotificationTrigger` (§6.3), `.active`, default sound, `userInfo["link"] = link.url.absoluteString`, no category. Delegate shows banners in foreground and routes taps.
  - Keeps `project.yml`, CI, Info.plist and assets correct.
- **May use:** everything (it is the integrator's shell), but only through the public initialisers in §2 and the view names in the module briefs.
- **Acceptance checks:** F4.1–4.5, F5.1 (opens on Goals), F12.1 (notification delivery), F13.1–13.2, F14, F15.1, F16.
