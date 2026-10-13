# State, economy, and recovery

## Backends and authority

`ServerConfig.Mode = "Simulation"` is honored only when `RunService:IsStudio()`.
The UI labels that backend **Studio simulation — progress is not saved**. Its
in-memory adapter, injected clock, and fixtures exercise the same voyage and
gameplay services used by live servers. Developer commands are a server-only
BindableFunction in ServerStorage, created only in Studio simulation.

Published servers always use DataStoreService and MemoryStoreService. The default
namespace is `MAM_TEST_V1`, intended for a separate private test universe. Choose a
different production namespace deliberately after verifying the live tests.
Robux products are not configured or activated. No Open Cloud key is required.

Profiles are read for presentation, but **never saved from a cached copy**.
Every persistent mutation goes through UpdateAsync on its authoritative key.
There is no profile session-lock/autosave mechanism to conflict with reward
workers. Snapshot caches are presentation-only. Atomic writes, bounded retry,
staggered refresh, and departure/shutdown presence cleanup replace stale
whole-profile saves. UpdateAsync callbacks do not yield; IDs, timestamps, random
choices, and server-obtained optional region codes are captured before them.

## Schema and keys

All records carry `schema = Config.SchemaVersion` (currently 1). Profile migration
adds missing fields while preserving existing balances, collection references,
settings, counters, and receipts. Existing collections count as having used the
free first hatch. Monster migration fills missing defaults while preserving
owner, identity, lifetime totals, active voyage data, and saved books. Unknown
newer schemas and ambiguous active records pause rather than overwrite data.

| Store | Key | Contents |
|---|---|---|
| `<namespace>_Profiles` | `p:<userId>` | Postage, owned IDs, outgoing reservations, inbox references, XP, tutorial, UTC requests/caps, settings, cosmetic ownership, eight placements, three display choices, receipts, activity fencing token |
| `<namespace>_Records` | `m:<two-digit hex partition>:<monsterId>` | Immutable owner, curated name and cosmetic seed/traits, state/version, current voyage, visual slots, earned appearances, lifetime summaries, recent books, durable operations |
| `<namespace>_Recovery` | `enumerator:<1..16>` | Last successfully completed page cursor and absolute checkpoint time for a discovery partition |
| MemoryStore `<namespace>_Presence` | account ID | Expiring eligibility hint, available capacity, internal server job; never exposed in public passports |
| MemoryStore `<namespace>_Queue` | monster ID | Disposable active-work hint |
| MemoryStore `<namespace>_Leases` | worker/partition name | Short-lived worker coordination; never custody or payout authority |

Canonical record keys hash the monster ID into one of 16 prefixes. This key layout
is the initial format of this project; it has not been run against an earlier
live unpartitioned store. No destructive migration/reset helper is shipped.

Public snapshots remove owner IDs, visited account IDs, custody tokens, internal
operations, receipts, and presence/server metadata. Public route labels are
anonymous humans or explicitly named fictional NPCs. Optional country/region
codes come from Roblox's server API only after opt-in; API failure simply omits
the code. IP addresses and precise location are never requested or stored.

## Durable transitions

| Transition | Canonical preconditions and commit | Follow-up / recovery |
|---|---|---|
| Egg → HOME | Profile's expected hatch sequence matches; capacity/balance checked atomically; persist new ID/record in `pendingHatches`, owned reference and payment together | Create canonical monster idempotently; remove pending record. Login and online maintenance repair a interrupted creation without buying another egg. Replayed sequence cannot buy a second egg. |
| HOME → LAUNCH_PENDING | Immutable owner, HOME, expected version and no unpaid previous operations; persist voyage and stable launch operation based on canonical version | Atomically reserve deposit/outgoing capacity in profile. Per-account practice reservation prevents concurrent free practices. |
| LAUNCH_PENDING → QUEUED | Matching launch operation and uncancelled preparation | Mark profile reservation finalized and enqueue hint. Missing hint is rediscovered by canonical enumeration. |
| Cancel launch → HOME | Persist cancellation on that exact pending launch | Profile refund and launch-version floor atomically fence stale reservation workers; clear matching outgoing/practice reservation, then return the canonical monster HOME. Retry uses a new version/operation. |
| QUEUED → HELD | Reserve inbox slot, then conditional canonical update checks state, version, voyage, deadline and eligibility | Persist holder/token/hold expiry; finalize reference. Losing race removes its exact reservation. A delayed claim whose reservation disappeared is rebuilt from canonical custody; if its slot filled, revoke that exact token and requeue. |
| HELD → QUEUED / RETURNING | Check assigned account, profile reference token, voyage/version, unexpired hold/deadline, unlocked souvenir, non-owner and no earlier contribution | Commit one appearance, passport event, visited account and human hop plus stable payout IDs together. Release/expiry commits no contribution or human income. Return at target or deadline. |
| RETURNING → HOME | Pending hop allocations/operations must settle first | Save voyage book and homecoming outbox, clear active voyage, then deliver deposit and eligible bonuses atomically to owner's profile even while offline. |

No MemoryStore queue visibility or worker lease grants custody. The canonical
conditional update is the deciding authority in competing claims, forwarding,
expiry, and recall. Incoming capacity is three; returning owned monsters use
their collection storage rather than mailbox slots. Normal plans cost 20,
qualifying human couriers receive 5, and homecoming refunds 20 plus 5 for each
durably eligible owner hop. NPC/objective grants are separately labeled.

Receiving and forwarding never debit Postage. An account contributes at most once
per voyage, and the owner is excluded. The visited set resets on a new voyage;
the monster's permanent ownership and lifetime history do not.

## Outbox, receipts, UTC caps, and interruption windows

Forwarding commits durable `carrier`, `ownerAllocation`, and inbox cleanup
operations to the monster. Homecoming commits its own payout operation. Delivery
records the receipt, allowance allocation, and balance/stat change together in
the recipient's profile. A retry sees the same receipt and cannot pay again.

Owner eligibility is allocated using the human event's UTC completion day before
homecoming totals are finalized. Carrier allowances use the same event time.
Historical human hops keep counting when the 20-carrier/40-owner daily allowances
are exhausted. Delayed homecoming does not move an allowance to a new day. Caps
retain up to 64 historical credited-day buckets; a monotonic floor closes older
days conservatively, so delayed allocation cannot reopen a discarded day.

Receipt acknowledgement follows canonical delivery. Only acknowledged receipts
are compacted at the configured threshold, and profile receipt epochs fence
already-running stale workers after compaction. Unacknowledged receipts remain
retryable; excessive unresolved receipts pause payment rather than drop it.

Shop ownership is its receipt: repeated purchases of an owned cosmetic do not
charge again. Request claim bits share the atomic currency grant; the daily board
can move forward in UTC only, so a delayed old-day callback cannot reopen claims.
Launch intents carry the server-issued expected monster version; recall intents
carry the voyage ID. An old request therefore cannot launch or recall a later
voyage after its original trip has completed.
Journal milestone claim bits share an atomic cosmetic/XP grant. Only server-earned
discoveries and owned references count. Normal and practice voyage completion
totals are recorded separately. Fictional NPC stops cycle cosmetic variants and
destinations on later voyages, giving solo players access to journal discoveries.
Activities reserve a server-issued durable session token. Final completion and
grant share an update; a newer session fences every older server's delayed final
callback. Activity progress is temporary, but completed rewards and counters
persist. Leaving/rejoining restarts an unfinished activity safely.

The automated fault matrix interrupts launch, forward and return writes before
and after commits. Adversarial tests race claims, recall, forwarding, payouts,
receipt compaction, and hatch sequences. Those are simulation evidence; actual
Roblox service throttling/concurrency remains a separate live acceptance test.

## Discovering work when hints disappear

Each worker rotates through the 16 canonical key prefixes. It acquires a short
lease for that partition, loads its durable checkpoint, and enumerates a page of
at most 12 records using ListKeysAsync. It processes that page idempotently and
advances the saved cursor **only after the entire page succeeds**. At the end of
the prefix the cursor clears, so the next pass discovers newly added keys too.
Other partitions have independent checkpoints and leases.

There is no registration crash window: creation writes the authoritative record
directly under a discoverable prefix. A crash before enqueue, a lost hint, or an
expired MemoryStore entry leaves that record discoverable. A crash mid-page
replays the page from the previous checkpoint. An expired/reacquired worker lease
may repeat work or move a checkpoint backward; conditional transitions and
receipt fencing preserve correctness, and later cycles cover the prefix again.

Recovery runs at a configured 30-second interval, ordinary hints at about
10 seconds with jitter. Budget checks bound per-page/per-operation work, and
service calls use three attempts with exponential delay plus jitter. Presence
refresh and background work preserve 40 read/20 write-budget units for player
actions; presentation refreshes also check their estimated cost before reading.
Actual live throughput and service throttling still require the published test.
Presence expires after 90 seconds, hints after one hour, and leases after 25 seconds.
Held records are also enumerated, so expired custody and missing inbox references
recover without relying on hints. Online maintenance repairs pending eggs and
tutorial visitors as well as stale reservations. Owner login processes their
known collection immediately; it does not scan the whole database.

Presence uses random sort scores refreshed on heartbeats, samples up to 100
online hints, then shuffles eligible candidates before conditional reservation.
This samples couriers from the experience's shared cross-server pool; recipients
cannot be chosen by a client. Hints and scores confer no reward or priority.
Random matching reduces predictable collusion; it does not eliminate alternate
account farming.

Recovery latency grows with backlog, service budgets and number of running
workers. No fixed recovery-time promise is made for a large/outage backlog. If
all servers stop, **nothing runs in the background**. Absolute deadlines are
enforced when records are processed after servers resume or the owner reconnects.
NPC events are unmistakably fictional and never increase human-hop totals;
normal NPC stories are bounded to three postcards. Practice catch-up reconstructs
its three scheduled fictional stops before its roughly 75-second homecoming.

## Bounded data and production failures

Collections allow 12 monsters. Every active voyage retains all meaningful events;
the maximum eight human hops plus three NPC postcards and departure/return fit
within the configured 24-event budget. At most one souvenir renders in each of
three visual slots; the passport retains replaced contributions. Each monster
archives the ten most recent complete voyage books plus lifetime human hops,
completed-voyage totals, and the set of earned appearances. Older completed books
are discarded on return; active books are never trimmed.

Live service failures propagate a retry result. No failure switches a published
server to simulation or replaces an unreadable profile with defaults. A committed
action whose response is lost may initially show an error; refresh/reconciliation
reveals its canonical outcome. Dispatch effects run only after the server returns
an accepted durable action. The UI remains able to retry, and operations remain
recoverable. See [TESTING.md](TESTING.md) for measured checks and unrun platform
requirements.

Official API references checked during implementation:

- [DataStore ListKeysAsync](https://create.roblox.com/docs/reference/engine/classes/DataStore#ListKeysAsync)
- [DataStoreKeyPages Cursor](https://create.roblox.com/docs/reference/engine/classes/DataStoreKeyPages#Cursor)
- [MemoryStoreSortedMap](https://create.roblox.com/docs/reference/engine/classes/MemoryStoreSortedMap)
- [Roblox publishing](https://create.roblox.com/docs/production/publishing/publish-games-and-places)
