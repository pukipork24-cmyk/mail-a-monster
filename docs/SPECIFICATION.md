You are the Roblox development agent responsible for building this game from the available project through a tested, playable release candidate. Implement the game, assets, interface, persistence, and tests. Do not stop after a design document, scaffold, scripts that have not been connected, or a list of instructions for me to implement.

Use the working title MAIL A MONSTER and the tagline:
“Little monster. Big adventure. Send a smile.”


1. HOW TO EXECUTE THIS TASK

- Inspect the existing place, repository, instructions, and your available Roblox Studio tools first. Preserve useful existing work. If there is no project, create one.
- Work through the milestones below in order and continue without asking me to approve ordinary implementation decisions. Choose reasonable defaults and document them.
- Create all required geometry, monster models, UI, effects, animations, scripts, and configuration. A clean procedural art style made from Roblox primitives is acceptable and preferred over missing assets or untrusted Toolbox models.
- Use current supported Roblox APIs; check official documentation where needed. Never invent asset IDs, product IDs, successful tests, or tool capabilities.
- Use Studio directly if your tools support it. If you have only filesystem access, supply a complete Rojo-compatible source project, pinned tooling, and a built place file when possible. Clearly identify any Studio playtest you cannot execute. A filesystem build alone does not prove that gameplay works.
- Each cloud task is already isolated. Use its existing checkout; do not create a Git worktree unless I request one.
- Keep an implementation checklist and update it as you work. Resolve errors, rerun affected tests, and continue until the acceptance criteria pass or a specific external platform requirement blocks further progress.
- If a platform setting or credential requires me, complete independent work first, provide the exact remaining action, and distinguish tested features from untested ones. Never request secret values in chat.
- Do not publish the experience publicly or activate real-money purchases without explicit authorization. A local place and private test experience are sufficient for development.


2. THE GAME AND ITS NONNEGOTIABLE RULES

Players hatch expressive little monsters, launch them from an absurd postal cannon, receive other players’ visitors, attach one souvenir, and send them onward. Every voyage creates a passport and a visible transformation. The owner receives a homecoming replay and rewards, then can display that monster or send it on another trip.

Ownership is permanent. A visitor is temporarily in a courier’s care; it is never traded, stolen, sold, deleted, or adopted. Every voyage has a hop target and an absolute return deadline. Homecoming is a deliberate system transition, not the chance of randomly selecting the owner.

Receiving, attaching a basic souvenir, and forwarding are free. Charge Postage only for launching one of your own monsters. Never trap a visitor because its courier has no currency.

A human hop occurs only when an eligible assigned player selects a souvenir and successfully forwards the visitor. Receiving, reconnecting, an expired hold, retries, and NPC travel do not count as human hops.

Each account may contribute once per voyage. Exclude the owner from carrier rewards and assignments. Account eligibility resets on the next voyage; the monster retains its lifetime identity and memories.

Match randomly among eligible players across the same experience’s running servers. Players cannot choose a recipient or target a friend. Random matching reduces predictable collusion but is not sufficient protection against farming.

Keep the experience friendly, accessible, and playable with one player. Use explicitly labeled NPC couriers when human traffic is unavailable. Never present NPC activity as real players, real countries, or human-hop achievements.


3. FIRST SESSION AND THE MOMENT-TO-MOMENT LOOP

Build a guided first session that demonstrates the complete loop in roughly five minutes:

1. Spawn facing the hatchery, mailbox, and cannon. Give a free egg and 40 Postage. Keep instructions short and contextual.
2. Hatch within the first minute. Choose a name from a curated list containing names such as Gerald, Pickle, Noodle, Miso, and Wobble. Show its personality through movement and expression.
3. Receive an unmistakably labeled NPC tutorial visitor. Open its passport, choose a free souvenir, and fire the cannon.
4. Complete one short island activity and learn how Postage works.
5. Launch the player’s own monster on a clearly labeled accelerated “Practice Voyage.” Show three fictional NPC postal stops, then return it in about 60–90 seconds.
6. Play the first homecoming replay, award one starter decoration, and introduce normal voyages and the collection journal.

Persist tutorial steps and its one-time rewards. Rejoining must resume safely. The practice voyage must be distinguishable in data, UI, and statistics; it earns no normal human-hop income. It cannot run concurrently with a normal voyage for that monster. Experienced players can skip guidance and obtain its one-time starter benefits safely.

During ordinary play, visitors arrive with a mailbox bounce, a parcel reveal, a recognizable monster reaction, and a concise passport preview. Attaching a souvenir visibly changes the monster before launch. The cannon should have anticipation, squash, recoil, a parcel trail, and a satisfying departure.

Dispatch animations begin only after the server accepts the durable action. A failed request leaves the monster in a recoverable state and displays a useful retry message.


4. WORLD, ART, AND LAUNCH CONTENT

Build one cohesive floating postal archipelago with a shared central post office and eight personal island plots. Set the intended server size to eight and handle joins, departures, and plot reassignment. Each player owns persistent island decoration data; plot geometry is temporary.

Use warm cream, teal, coral, lavender, and sky-blue colors; rounded silhouettes; oversized postal machinery; envelope motifs; and readable signs. Give the scene intentional lighting, clear paths, a sky, and restrained particles. Players should immediately identify interactive objects.

Each island needs a hatchery, mailbox, launch cannon, monster display area, decoration anchors, and access to activities. The central post office contains the souvenir journal, cosmetic shop, voyage board, and tutorial guide NPC. Include spawn recovery and protection against getting stuck or falling indefinitely.

Implement at least:

- Four monster body families, six color palettes, four face styles, and four personalities: Curious, Sleepy, Dramatic, and Mischievous. Traits are cosmetic.
- Idle, happy, startled, packing, and homecoming reactions. Lightweight procedural animations are acceptable.
- Twelve visibly distinct souvenirs: four hats, four accessories, and four patches or cosmetic mutations. Make every attachment work on every body family.
- Twelve fictional destination stamps, twelve island decorations, three cannon finishes, and three mailbox styles.
- Three fully working activities: Parcel Sorting, Postal Flower Watering, and Floating Letter Collecting.

Preserve the monster’s identifiable body, face, and personality. At most one souvenir per visual slot is rendered; all contributions remain in that voyage’s passport. A new item can replace an item visually without erasing the older entry. Mutations must be harmless visual variants that fit the same slot budget.

Use fixed decoration anchors with preview, place, replace, and remove controls. This gives players meaningful expression without requiring a large free-placement building system. Save ownership and placements. Other players can visit and see the island, but only its owner can edit it.

Create assets locally where practical. Imported assets must be permitted for use and inspected for unwanted scripts. Sound assets must use verified permitted IDs; missing optional audio must not prevent play. Include music/SFX controls and visual equivalents for sound cues.


5. ACTIVITIES, PROGRESSION, AND REPLAYABILITY

Activities should take about 30–60 seconds, work on touch, and award 5–10 Postage for server-validated completion:

- Parcel Sorting: select matching labeled bins for a short sequence of parcels. Use shape/icon labels as well as color.
- Postal Flower Watering: visit and water a small sequence of flower beds, with server checks for order, distance, and minimum elapsed time.
- Floating Letter Collecting: follow a short accessible route, collecting a server-issued set of letters. Avoid demanding jumps.

Track activity sessions and reward claims on the server. Remote spam, impossible timing, or touching another player’s objective must not grant money. Activities remain available while all owned monsters are traveling.

Add the following progression systems:

- A souvenir album that records discovered designs and fictional stamps. Discovery is earned by real gameplay, persists, and opens detail cards with acquisition context.
- A monster collection with lifetime human hops, voyages completed, earned souvenir appearances, and replayable recent voyage books. Owners can choose previously earned appearances while the monster is home.
- Courier levels that unlock additional free souvenir choices and cosmetic shop items. Levels do not improve recipient priority or earnings per hop.
- Three rotating daily requests with activity-based alternatives, such as “Forward two visitors OR finish three sorting rounds.” No missed-day penalty or streak reset.
- Voyage objectives such as “Bring home a hat” or “Collect two souvenir families.” Give a low-population alternative using explicitly fictional NPC postcards. NPC alternatives award the stated modest cosmetic/objective reward, not human-hop income.
- Home island expression through decorations, display perches, mailbox styles, and cannon finishes.

Use these voyage plans, with all values centralized in configuration:

Short Hop:
- Available immediately.
- Costs 20 Postage.
- Returns after 3 human hops or 6 hours.

Grand Tour:
- Unlocks at courier level 3.
- Costs 20 Postage.
- Returns after 5 human hops or 24 hours.

Expedition:
- Unlocks at courier level 6.
- Costs 20 Postage.
- Returns after 8 human hops or 48 hours.

Allow two concurrent outgoing voyages and three incoming visitor slots per player. Unlock a third outgoing voyage through ordinary play at level 5. Collection storage and homecomings must never be blocked by incoming mailbox capacity. Support at least twelve owned monsters, with enough separate return storage for every dispatched monster.

Each holder has at most 24 hours to forward, bounded by the voyage deadline. Expiration forwards automatically without a contribution or carrier fee. At the hop target or voyage deadline, return the monster to its owner’s home collection. If the owner is offline, queue its homecoming presentation and reward claim for the next login.

When there are no eligible humans, use bounded NPC story events at a configurable interval, initially five minutes. Record up to three NPC postcards per voyage; NPCs never inflate human-hop counts. Continue trying for human couriers. A player may request an early return after ten minutes; first resolve any in-flight transition safely, then pay only rewards already legitimately earned.

Store absolute timestamps. When no game server exists, nothing executes. Process overdue work when a server next runs or the owner reconnects. Explain this honestly in development documentation; never promise a background scheduler Roblox does not provide.


6. ECONOMY AND MONETIZATION BOUNDARIES

Use a single earnable currency named Postage. Start with 40, a free first monster, and the tutorial visitor. Additional random-trait eggs cost 80 earned Postage. Make all traits cosmetic, show available possibilities, and use no Robux-funded random eggs in this build.

Default rewards:

- A qualifying manual human forwarding earns its courier 5 Postage once for that voyage.
- Homecoming returns the 20 Postage dispatch deposit and awards 5 per reward-eligible human hop, up to the plan’s target.
- NPC travel and automatic forwarding generate no normal carrier or owner hop income. An NPC-only return refunds the dispatch deposit.
- Tutorial rewards, requests, and collection milestones are separate one-time or bounded grants with stable receipt IDs.
- Decorations cost roughly 50–300 Postage; basic souvenirs and forwarding remain free.

Cap normal carrier payouts at 20 eligible handoffs per account per UTC day, and owner hop bonuses at 40 credited hops per account per UTC day. Keep historical human-hop counts separate from reward eligibility. Snapshot or durably allocate eligibility when a hop completes so delaying homecoming cannot bypass caps. Show when the daily reward limit has been reached while still allowing free forwarding.

Add server-side action limits, dispatch cooldowns, no self-rewards, no repeat contribution during one voyage, and idempotent grants. Keep economy values tunable in one module. Do not claim to eliminate alternate-account abuse.

Build a functioning in-game cosmetic shop using Postage. Structure optional future Robux products around direct-purchase cosmetic bundles and extra display space. Paid income-bearing mailbox slots undermine the economy; do not sell increased reward throughput, targeting, hops, return speed, or better matching.

Keep paid products hidden until real product IDs are configured and their purchase/grant path is implemented and tested. Do not display broken buy buttons or placeholder prices. Monetization integration must not block the free playable game.


7. PASSPORT, GEOGRAPHY, AND HOMECOMING

The passport must show the monster’s portrait and name, voyage number, human-hop count, remaining time, human versus NPC event labels, ordered souvenir contributions, fictional stamps, and current broad status.

Default to fictional postal islands. Optionally let each courier opt into sharing a coarse country/region stamp obtained using Roblox’s supported server-side country/region API. Obtain explicit opt-in before appending it. Handle API failure and unavailable regions without blocking play; never substitute invented human geography. Use supported flag artwork where available and a readable country/region code fallback.

Do not store IP addresses, precise location, or expose a courier’s current server. Keep internal user IDs server-side. Public route events should use anonymous courier labels; NPCs have unmistakably fictional names and an NPC badge. No country-specific requirements or rewards.

Use curated monster names and preset reaction stamps for this version. If adding free text later, implement Roblox’s required server-side filtering and failure behavior first. Do not add a custom unfiltered chat system.

Homecoming opens a 10–20 second replay reconstructed from saved events: departure, each meaningful contribution, appearance changes, and the final reveal. Provide pause/skip and an instant-summary option. Use an illustrative postal route, clearly distinct from an exact real-world GPS route. Let the owner replay it later without receiving another reward.

End on a before/after portrait, travel statistics, item discoveries, an itemized payout, and actions to display the monster or plan its next voyage. A clean “Photo View” hides normal HUD controls for player screenshots; no external upload or recording integration is required.


8. COMPLETE INTERFACE AND ACCESSIBILITY

Implement actual working screens for the HUD, hatch reveal, monster collection, mailbox, visitor contribution, passport, voyage selection/tracking, homecoming, souvenir album, requests, shop, decoration placement, tutorial, and settings.

Every action must have success, loading, empty, full-capacity, and recoverable-error states where relevant. Block duplicate submissions locally for usability and independently on the server for correctness. Make disabled controls explain the reason.

Support keyboard/mouse and touch as required platforms. Use Roblox’s supported input abstractions so basic gamepad navigation also works. Include visible interaction prompts, mobile-safe controls, scrolling, appropriate safe-area handling, readable type, and generous touch targets. Gameplay must not depend on hover or color alone.

Provide reduced motion, music/SFX volume, camera shake toggle, optional country-stamp sharing, and visitor acceptance on/off. Turning acceptance off stops new assignments; existing visitors remain forwardable or may be returned to the pool without a reward.

Limit simultaneously rendered monsters and accessories. Reuse models where practical, avoid unnecessary per-frame loops, disconnect event listeners, and clean up temporary effects. Test the intended eight-player scene and mobile layout. Report measured performance when measurement is available rather than asserting a universal frame rate.


9. CODE STRUCTURE AND AUTHORITATIVE STATE

Use modular Luau and strict types where supported. Keep configuration, definitions, network types, and pure validation separate from server services and client controllers.

A reasonable structure is:

ReplicatedStorage/MailAMonster/
  Shared:
    Config
    Types
    MonsterCatalog
    SouvenirCatalog
    EconomyRules
  Remotes:
    Explicit validated request/response and update channels
  Assets:
    Models, UI templates, effects

ServerScriptService/MailAMonster/
  Bootstrap
  PlayerDataService
  MonsterService
  VoyageService
  MatchmakingService
  MailboxService
  RewardService
  RecoveryService
  ActivityService
  ProgressionService
  IslandService
  TutorialService
  Storage adapters and test helpers

StarterPlayer/StarterPlayerScripts/MailAMonster/
  UI controller
  Input controller
  MonsterRendering controller
  Cannon controller
  Replay controller
  Activities controller

You may simplify names and combine small modules, but keep durable state transitions testable without UI.

Clients send intents only. The server validates identity, ownership/custody, expected voyage and version, capacity, elapsed time, distance where relevant, souvenir IDs, unlocks, balances, and request rates. Reject malformed types, oversized payloads, NaN/infinite numbers, arbitrary Instance references, and unauthorized IDs.

Never accept client-provided reward values, country codes, hop counts, recipients, or completion claims as authoritative.

Use stable server-created operation IDs. New client request IDs must not allow replaying an already completed transition. Clients receive only the data needed to render their own collection, current visitors, and sanitized public views.

Player data includes:
- Schema version.
- Currency and reward caps.
- Owned-monster references.
- Inbound and outgoing references.
- Collection discoveries.
- Cosmetic ownership and placements.
- Tutorial and request progress.
- Settings.
- Pending receipts and operations.

The authoritative monster record includes:
- Schema version.
- Monster ID and immutable owner ID.
- Cosmetic seed, traits, and name.
- Lifetime summaries.
- Current voyage ID and number.
- State and state version.
- Plan and timestamps.
- Custodian and claim token.
- Visited contributor IDs.
- Bounded route events.
- Souvenir state.
- Pending reward and repair operations.

Implement schema migration, safe defaults, and bounded data. Do not overwrite existing player data with defaults after a load failure. Preserve every active voyage event; archive at least the ten most recent completed voyage books plus lifetime summary totals, documenting the retention policy.


10. CROSS-SERVER DELIVERY AND DURABLE RECOVERY

This is a required core feature. A same-server array or fake global label does not satisfy it.

Use DataStoreService for durable authoritative records. Use MemoryStoreService for temporary matching hints, online courier presence, and worker leases. MessagingService may accelerate notifications, but correctness must not depend on receiving a message. Check current limits and service budgets before choosing batch sizes and polling rates.

Implement an explicit state machine, including recoverable launch preparation:

HOME -> LAUNCH_PENDING -> QUEUED -> HELD
HELD -> QUEUED or RETURNING
RETURNING -> HOME

For each transition, define preconditions, the canonical UpdateAsync mutation, the stable operation ID, and how interrupted work is recovered.

UpdateAsync callbacks must be pure, non-yielding, and safe to rerun. Generate stable IDs outside them and perform secondary writes through persisted operations.

Claiming or forwarding uses conditional UpdateAsync checks against voyage ID, state version, custodian, and claim token. Queue invisibility alone is insufficient. Two servers racing must not obtain valid custody of the same monster. An expired or revoked token cannot attach a souvenir or forward.

Matching selects eligible active players with available inbox capacity across servers. Exclude the owner, previous contributors for that voyage, players declining visitors, and unavailable/full recipients. Randomize eligible selection; avoid always favoring the fastest-polling server.

Assignments persist when a recipient leaves, until forwarding or expiry. A new login reconciles stored visitors before requesting more.

Inbox entries and queue entries are references, not custody authorities. Reserve capacity safely and repair stale reservations. Revalidate canonical custody before showing an actionable visitor; never create an actionable duplicate from an old inbox reference.

MemoryStore data can disappear. Implement and test a concrete durable discovery/recovery mechanism.

For example:
- Use discoverable canonical record keys with budgeted, checkpointed, partitioned DataStore enumeration and disposable active-work indexes.
- Alternatively, use a bounded durable sharded directory with recoverable registration.

Document the chosen algorithm and crash windows. Do not merely write “add reconciliation later.”

Recover monsters after:
- A crash between a durable transition and enqueue.
- Lost queue hints.
- Expired MemoryStore entries.
- Interrupted inbox assignment.
- Missed deadlines.

Recovery must use bounded work, backoff, jitter, service budgets, and durable progress where needed. Avoid a full database scan on every join or every frame.

Roblox does not provide a transaction spanning arbitrary DataStore keys. Handle launch charges using an idempotent reserve/finalize/refund operation. A failed or retried launch cannot destroy a monster or permanently take its deposit without a recoverable voyage.

Commit forwarding/history changes and stable payout-event IDs in the monster’s authoritative transition. Deliver payouts through a durable retryable outbox.

In the player’s authoritative update, record the receipt and balance change together. Respect any profile session ownership mechanism; do not let separate services write stale copies of a loaded profile. A duplicate payout event must not credit money twice.

Apply the same rigor to:
- Homecoming.
- Daily caps.
- Request rewards.
- Shop transactions.
- Tutorial grants.
- Early returns.

Receipt retention/compaction must not make old pending events payable again. Log operation IDs and diagnostic errors without exposing secrets or personal data.

Use load/save retries with bounded backoff, staggered autosaves, shutdown handling, and safe release of session locks. Handle throttling and outages explicitly.

In production, storage failure must pause affected persistent actions and offer retry. Never silently switch to in-memory storage while claiming success.


11. DEVELOPMENT AND TEST MODES

Provide two explicit backends behind the same service interfaces:

A. Studio simulation:
- Deterministic in-memory storage and matching adapters.
- Fake clock.
- Fixtures for solo play, two couriers, NPCs, errors, and duplicate requests.
- Visible “Studio simulation — progress is not saved” indicator.

B. Live/test services:
- Actual DataStore, MemoryStore, and cross-server behavior.
- A separately isolated test universe or safe test namespace.
- No destructive test helpers against production data.

Simulation mode must be enabled only by a server-side development setting and a Studio/test-environment guard. Accelerated timers, currency grants, and debug controls must be inaccessible to ordinary production clients.

Provide developer commands to:
- Create a test monster.
- Enqueue it.
- Advance the fake clock.
- Expire a holder.
- Simulate a service error.
- Remove a queue hint.
- Retry a payout.
- Reset only the explicitly isolated test data.

Make these useful for repeating the acceptance tests, not required for normal gameplay.

If Studio API access or publication is needed for a specific real-service test, document the exact setting. Use simulation to finish independent gameplay work, but never describe simulated storage or local multi-client testing as verified live cross-server delivery.


12. IMPLEMENTATION MILESTONES — CONTINUE THROUGH ALL OF THEM

1. Establish the project, configuration, storage interfaces, state-machine tests, and a navigable island.
2. Finish a complete solo practice loop: hatch, receive, attach, fire, return, replay, and save/reload where available.
3. Implement real multi-player and cross-server custody, rewards, recovery, deadlines, and low-population NPC behavior.
4. Finish all launch content, activities, progression, collection, cosmetics, requests, and island decoration.
5. Finish mobile UI, animation, sound integration, accessibility, performance cleanup, and failure states.
6. Execute acceptance tests, fix defects, rerun affected checks, and deliver the playable project with setup and testing documentation.

Do not defer required delivery reliability until after visual polish. Do not stop after milestone 1 or 2 and label the game complete.


13. ACCEPTANCE TESTS

Run tests and record actual results. Include automated pure-logic/service tests where possible and Studio playtests for the world and UI.

At minimum verify:

1. A brand-new player completes the guided practice loop in roughly five minutes without developer commands.

2. A solo player can hatch, use all activities, buy/place a decoration, receive an NPC visitor, and complete a voyage with honest NPC labeling.

3. Two distinct players complete a real handoff:
   A owns the monster.
   B receives it.
   B adds exactly one souvenir and forwards.
   A’s ownership never changes.
   The saved passport records the correct event.

4. In a published private test experience, two distinct server jobs complete a real transfer. Verify distinct JobIds in developer logs and persistent continuity. If unavailable, mark this test unrun and the cross-server feature unverified.

5. Simultaneous claims, double-click forwarding, repeated remote calls, and stale claim tokens cannot duplicate custody, souvenirs, hops, charges, or rewards.

6. Simulated interruption before and after each durable launch/forward/return commit recovers without lost monsters or duplicate money.

7. Removing queue hints and restarting workers still discovers and delivers pending monsters.

8. A holder leaving, a full mailbox, visitor opt-out, no eligible humans, and an owner remaining offline do not strand monsters permanently.

9. The 24-hour hold limit, voyage deadline, target-hop homecoming, and early recall work using a fake clock. Missed deadlines recover when servers resume.

10. Rejoining restores owned monsters, active voyages, actionable visitors, currency, cosmetics, island placements, requests, tutorial progress, and settings.

11. Replaying a homecoming or repeating a reward event never grants a second payout. Reward caps survive rejoining and concurrent events.

12. NPC events, auto-forwarding, the owner, repeat couriers, and invalid activity completions do not earn human-hop rewards.

13. Data load/save throttling and failure produce honest retry states. No default-data overwrite or false delivery confirmation occurs.

14. Unsupported souvenir IDs, remote spam, forged recipients, impossible activity timing, and unauthorized island edits are rejected.

15. All four monster families support all twelve souvenirs without broken attachments. Accessory and history budgets remain bounded.

16. Core screens and activities work with desktop and mobile input. Reduced motion and muted audio preserve essential feedback.

17. An eight-player test scene has no persistent script errors, broken interaction paths, runaway instances, or obvious progressive memory growth during a meaningful session.

For every test, report PASS, FAIL, or NOT RUN with evidence. Fix failures you can reproduce. Do not substitute “the code should work” for a test result.


14. FINAL DELIVERABLES AND COMPLETION STANDARD

Deliver:
- The complete playable place/project.
- All source and generated assets.
- Reproducible setup/build steps.
- Centralized balance configuration.
- Storage schema and recovery documentation.
- A concise test report.
- The exact way to open, start, and test the game.
- Any platform settings still required.

Provide a concise handoff explaining what is playable, how to run it, which real-service tests passed, and any remaining external blockers. Keep release claims aligned with evidence.

A fully tested simulation is a useful local deliverable; it does not establish that the live global relay has passed.

The game is complete for this assignment when a normal player can enjoy the full loop, the specified content and progression work, data persists safely, and the required live-service tests have passed.

If your tools prevent that final verification, finish all independent implementation and explicitly identify the smallest remaining verification step.

Start by inspecting the available project and tools, then implement the game. Continue working until it is playable; do not respond with only a plan.