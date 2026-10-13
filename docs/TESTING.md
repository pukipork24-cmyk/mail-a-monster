# Test report and reproducible playtest matrix

This report separates executable cloud checks from Roblox Studio and live-service
tests. A generated `.rbxlx` file and passing simulated services do not establish
that the game has passed a rendered playtest or real cross-server relay.

## Cloud checks

Run from the repository root:

```sh
python3 tools/setup.py
python3 tools/check.py
python3 tools/build.py
python3 tools/package.py
```

- PASS: pinned Rojo 7.7.1 and Luau 0.698 installed on Linux x86_64; official
  release SHA256 digests verified before extraction.
- PASS: all **24** source/test Luau files compile with the pinned Luau compiler.
- PASS: `tests/core.luau` — **19** service groups, including **48 confirmed**
  interruption scenarios across all measured launch, forward, and homecoming
  writes. Each before/after-commit case asserts that its target fault fired.
- PASS: `tests/concurrency.luau` — **25** adversarial custody, recall, payout,
  and receipt-compaction checks using competing simulated workers.
- PASS: `tests/gameplay.luau` — **147** activity, progression, shop, receipt,
  settings, and failure/retry checks.
- PASS: `tests/hardening.luau` — **76** hatch/voyage replay, migration, missing-inbox
  repair, 16-partition lost-hint recovery, UTC fencing, and display checks.
- PASS: `tests/integration.luau` — **104** checks of the guided service loop:
  free hatch → labeled NPC visitor → all three timed activities → practice
  postcards/homecoming → one-time decoration → purchase/place → service reload.
  This uses fake time/proximity and is not a timed Studio playtest.
- PASS: `tests/validation.luau` — **180** malformed payload, exact-field schema,
  finite value, unauthorized field, and rate-limit checks.
- PASS: pure Config/Catalog/Validation/RateLimiter modules pass Luau's static
  analyzer. Roblox-dependent modules were compiled, not fully type-checked
  against an installed Studio engine definition set.
- PASS: genuine Rojo place build; XML parses and contains **1 server script,
  1 client script, and 16 modules**, correctly mapped into Roblox services.
- NOT RUN: Roblox Studio runtime, rendered world/UI, mobile input, eight-player
  performance, actual DataStore/MemoryStore access, and distinct live-server
  transfer. Roblox Studio is unavailable in this cloud workspace.

## Required acceptance matrix

Record PASS, FAIL, or NOT RUN with observed evidence and a place version for every
row. Automated subchecks can support a row; they do not replace its Studio or
real-service requirement. Until a tester records evidence, these integrated rows
remain NOT RUN where a rendered/platform check is required. PASS (simulation)
means the stated service-level behavior executed; the adjacent runtime/live
check is still unrun.

| # | Required test | Current integrated status | Reproduce / evidence to collect |
|---|---|---|---|
| 1 | New-player guided loop in roughly five minutes | NOT RUN — Studio required | New simulation session, use no developer commands, time hatch → tutorial visitor → activity → Practice Voyage → claimed homecoming. |
| 2 | Complete solo loop and all activities, shop, placement | NOT RUN — Studio required | Sort parcels, water every bed, collect letters; buy a decoration, preview/place/replace/remove it; finish NPC practice and normal voyage. Confirm NPC labels. |
| 3 | Two-player human handoff and permanent ownership | NOT RUN — Studio required | Local server with two players: A launches; B receives, equips one souvenir, forwards once; inspect saved book and A's ownership. |
| 4 | Real relay between distinct published server jobs | NOT RUN — platform required; cross-server feature unverified | Use isolated test universe, capture two different JobIds, complete A→B relay, reconnect both accounts, inspect passport/currency continuity. |
| 5 | Competing claims, duplicate forward, stale tokens | PASS (simulation); Studio remote test NOT RUN | Core/concurrency/validation suites reject duplicate/stale transitions. Repeat requests in a local two-player test for engine evidence. |
| 6 | Crash windows for launch, forward, and return | PASS (simulation); live outage test NOT RUN | 48 confirmed interrupted-write cases recover deposits, ownership, history and once-only payouts. |
| 7 | Lost MemoryStore hints / worker restart | PASS (simulation); actual MemoryStore NOT RUN | Core/hardening restart workers without hints and discover overdue records in all 16 partitions. Repeat in isolated live namespace. |
| 8 | Holder leaves, full mailbox, opt-out, solo, offline owner | PASS (simulation); Studio disconnect test NOT RUN | Core cases exercise persisted custody, three-slot capacity, opt-out and offline return. |
| 9 | Hold expiry, deadline, target hops, recall, downtime | PASS (fake-clock services); Studio/live NOT RUN | Core suite advances absolute thresholds; only manual eligible contributions earn hop money. |
| 10 | Rejoin restores all persistent data | NOT RUN — live services | Mode Live in isolated test universe; rejoin and compare owned/visitors/voyages/currency/cosmetics/placements/requests/tutorial/settings. Simulation resets by design. |
| 11 | Receipt idempotence and UTC caps | PASS (simulation); live concurrent budgets NOT RUN | Core/concurrency/gameplay/hardening cover replay, reload, caps, compaction and delayed previous-day callbacks. |
| 12 | No rewards for NPC/automatic/self/repeat/invalid steps | PASS (simulation); Studio presentation NOT RUN | Core/gameplay/integration verify zero human-hop income for NPCs, expiry, owner/repeat couriers and invalid steps. |
| 13 | Throttling/outage offers honest retry | PASS (fault injection); real throttling NOT RUN | Simulated before/after-commit failures pause/retry without default overwrite. Actual service access/budgets require live test. |
| 14 | Invalid IDs, spam, forged recipients, timing, edits | PASS (service/validation); actual remotes NOT RUN | 180 validation plus gameplay/core checks reject malformed inputs and unauthorized actions. Test the real RemoteFunction in Studio. |
| 15 | Four body families × twelve souvenirs; bounded history | NOT RUN — visual Studio check | Preview all 48 attachment combinations and each palette/face/personality. Check head/accessory/patch positions and ten-book retention. |
| 16 | Desktop/touch/gamepad navigation/accessibility | NOT RUN — device emulator required | Resize portrait/landscape; inspect scrolling and touch targets; complete activities; reduced motion/audio mute retain cues; test selection navigation. |
| 17 | Eight-player stability/performance | NOT RUN — Studio/live measurement required | Eight players for ≥15 minutes, repeated hatch/forward/UI/open/close/decorate/respawn; record errors, FPS, memory and instance counts at start/end. |

## Studio commands for repeatable simulation tests

Start **Play**, switch the Command Bar to **Server**, then use the non-replicated
`ServerStorage.MailAMonsterDevelopment` BindableFunction. These controls exist
only when `RunService:IsStudio()` and the server's simulation setting are both
true. They cannot be invoked by ordinary production clients. Commands never
reset or mutate a live test/production namespace.

```lua
local dev = game:GetService("ServerStorage"):WaitForChild("MailAMonsterDevelopment")
local userId = game:GetService("Players"):GetPlayers()[1].UserId
local snapshot = dev:Invoke("Inspect", userId)
local monsterId = snapshot.monsters[1] and snapshot.monsters[1].id
print(dev:Invoke("CreateMonster", userId, {name = "Gerald"}))
print(dev:Invoke("AdvanceClock", userId, {seconds = 600}))
```

Use the monster ID from `Inspect` when a command requires one; do not use its
display name as its durable ID. To check original geometry with the actual Studio
engine, run this in the Server Command Bar during Play:

```lua
require(game.ServerScriptService.MailAMonster.ArtChecks).run()
```

The provided harness checks 48 family/souvenir pairs at three scales plus 96
family/palette/face combinations, bounded parts/slots, all eight islands and
walkable activity points. It is **NOT RUN** in the cloud, and automated geometry
checks still require visual inspection of attachments and mobile readability.

| Command | Arguments | Purpose |
|---|---|---|
| `Inspect` | `{}` | Return a sanitized server snapshot for fixture IDs and state. |
| `CreateMonster` | `{name="Gerald"}` | Grant the egg cost in simulation and hatch through normal service logic. |
| `Enqueue` | `{monsterId="…", plan="ShortHop"}` | Launch a valid owned monster through normal validation. |
| `AdvanceClock` | `{seconds=600}` | Advance 0–604800 fake seconds and process recovery. |
| `ExpireHolder` | `{monsterId="…"}` | Expire canonical held custody and run worker recovery. |
| `ServiceError` | `{operation="updateProfile", count=1}` | Fail the next 1–5 matching storage operations. |
| `RemoveHint` | `{monsterId="…"}` | Remove a temporary queue hint, preserving canonical record. |
| `RetryPayout` | `{monsterId="…"}` | Redeliver durable outbox work to test receipt idempotence. |
| `ResetSimulation` | `{}` | Clear only this running in-memory fixture; reload joined players. |

For a clean reset of UI and geometry, Stop and Play again. Production has no
reset endpoint and no developer remote. Durable services use absolute timestamps;
if no Roblox server is running, no work executes until a server resumes.

## Distinct live-server proof

Follow [IMPORT.md](IMPORT.md) to publish a private test universe with authorized
editor accounts and the isolated `MAM_TEST_V1` namespace. Use two distinct player
accounts in **two running jobs of the same experience**. A two-client Studio
session shares one server and does not satisfy this test. The game logs its
server job when it starts; preserve server-log evidence from both jobs without
sharing internal player identifiers or credentials.

If ordinary joining places both accounts in the same job, create/use two separate
private server instances for this isolated test experience if the Roblox account
supports them, or use a developer-controlled reserved-server test harness. Do
not add a production recipient selector to perform this test. Distinct jobs are
a prerequisite, never inferred from different client windows.

1. Verify live backend and two unequal, nonempty `game.JobId` values.
2. Make B an eligible accepting courier with free inbox capacity; launch A's
   Short Hop and wait for matching. No human recipient is selected by the client.
3. B opens the visitor, attaches one free souvenir, and forwards once.
4. Record the canonical ownership, single human contribution, and expected
   once-only carrier payment. Rejoining restores continuity.
5. Finish the voyage through legitimate handoffs/deadline, verify the owner
   receives one deposit refund plus only eligible hop bonuses, and repeat claim.
6. Record place version, namespace, JobIds, timestamps, observed results, and
   relevant service errors. Until this is done, report cross-server as unverified.

## Mobile and performance evidence

Use Studio's device emulator for at least one narrow phone portrait and one
landscape phone, plus a desktop window. Check every screen, activities, safe
areas, loading/error/full/empty states, settings, and photo view. A physical
mobile session is preferred before release.

In an eight-player session record client/server memory, rendered instance counts,
script errors, and frame time over a meaningful interval. Compare after repeated
UI/reaction cycles and joins/departures to identify growth. No measured FPS or
universal performance claim is supplied by this cloud build.
