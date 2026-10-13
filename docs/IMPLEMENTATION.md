# Implementation checklist

- [x] Shared configuration, catalog, Rojo structure, tool pins
- [x] Pure transitions, durable storage and simulation adapters
- [x] Launch, custody, forwarding, returns, payout recovery
- [x] Procedural archipelago and all cosmetic content
- [x] Activities, requests, tutorial, shop, collections
- [x] Client interface, animation, accessibility implementation
- [x] Built place and automated checks
- [x] Studio/live test matrix and import/publishing handoff
- [ ] Roblox Studio rendered/first-session/mobile/eight-player acceptance
- [ ] Private published experience: persistence and two distinct live server jobs

Implementation and executable simulation checks are delivered. The final two
checks require Roblox Studio/accounts and remain NOT RUN. This is a test build,
not a verified public release. See TESTING.md for actual evidence and boundaries.

## Internal integration contract

Paths: `src/shared`, `src/server`, `src/client`. Shared modules live in
ReplicatedStorage.MailAMonster.Shared. Server modules live beside Bootstrap in
ServerScriptService.MailAMonster. Clients live in StarterPlayerScripts.MailAMonster.

Remotes: `ReplicatedStorage.MailAMonster.Remotes.Request` (RemoteFunction,
`InvokeServer(action: string, payload: table)`), and `Update` (RemoteEvent).
Responses `{ok: boolean, error: string?, data: table?, effect: table?}`.
Every successful action returns the new sanitized snapshot as `data`.
`Update` sends a full sanitized snapshot. Snapshot:
`{profile, monsters: array, visitors: array, serverTime, simulation, activity?}`.
Catalog/config are read directly by client, never supplied as authority by client.

Profiles (durable): `id` string, `currency`, `owned` array of monster IDs,
`inbox` map monster ID -> reservation, `outgoing` map,
`xp`, `tutorial` table (`hatched`, `visitor`, `activity`, `practice`, `claimed`, `skipped`),
`settings` (`reducedMotion`, `musicVolume`, `sfxVolume`, `cameraShake`, `shareCountry`, `acceptVisitors`),
`cosmetics` map ID -> true, `placements` map anchor string -> decoration ID,
`cannon`/`mailbox` style IDs, `album` map souvenir ID -> context,
`stamps` map stamp ID -> context, `requests` daily counters and claimed map,
`stats` (`forwards`, `activities`, `sorting`, `watering`, `letters`), receipts/caps.
Public profile omits internal IDs, receipts and operations; adds `level` and `daily`.

Monster: `id`, immutable `ownerId`, `name`, `body`, `palette`, `face`, `personality`,
`seed`, `state`, `version`, `voyageNumber`, `lifetimeHops`, `voyagesCompleted`,
`slots` map slot -> souvenir ID, `earned` map souvenir ID -> true, `books` array,
optional `voyage`: `{id,plan,practice,startedAt,deadline,hopTarget,deposit,humanHops,
rewardHops,visited,events,slotsBefore,holderId,claimToken,holdUntil,npcCount,lastNpcAt,objective}`.
Public monsters omit ownerId, visited, internal claimToken, operations. Visitor
actions contain `{monsterId, voyageId, version, souvenirId}`; server retrieves
the held claim token and verifies it against the canonical record.
Events `{kind,at,label,souvenirId?,stampId?,country?,humanHop?,rewardEligible?}`.
Book `{id,number,plan,practice,events,slotsBefore,slotsAfter,humanHops,rewardHops,
startedAt,returnedAt,payout,objectiveReward,claimed}`; no user IDs in events.

Actions: `Snapshot`, `Hatch {name,sequence}` (server's current profile.hatchSeq), `Launch {monsterId,plan,version,objective?}`,
`Forward {monsterId,voyageId,version,souvenirId}`, `Recall {monsterId,voyageId}`,
`ReleaseVisitor {monsterId,voyageId,version}`, `ClaimHomecoming {monsterId,bookId}`,
`Equip {monsterId,souvenirId}`, `Display {monsterId,perch}` (1..3), `Settings {key,value}`, `SkipTutorial {}`,
`ActivityStart {kind}` (`sorting`, `watering`, `letters`),
`ActivityStep {sessionId,target}`, `Buy {itemId}`, `Place {anchor,itemId}`
(empty itemId removes), `Style {kind,itemId}`, `ClaimRequest {requestId}`.
Journal milestones use `ClaimMilestone {milestoneId}`; their cosmetic and XP
grants share a durable once-only claim bit in the profile.

World module `World.build()` returns object with `assign(player,profile)`,
`release(player)`, `refresh(player,profile,monsters,visitors)`,
`getActivityPosition(player,kind,index): Vector3?`, `getPlot(player)`,
`destroy()`. Prompts have `MAMAction`, `MAMKind`, and optional `MAMTarget`
attributes on the ProximityPrompt (clients route these into UI/actions).
Activity positions are world-defined. Server validates distance.
MonsterFactory shared API `create(monster, scale?): Model` anchored geometry,
`applySouvenirs(model, slots)`, `react(model,reaction,reducedMotion?)`.

VoyageService API `new(storage,clock,options)`, `loadPlayer(userId)`,
`handle(userId,action,payload): result` for core actions,
`snapshot(userId): snapshot`, `tick()`, `playerLeaving(userId)`.
Storage methods `getProfile(id)`, `updateProfile(id, pureTransform)`,
`getMonster(id)`, `updateMonster(id,pureTransform)`, `createMonster(record)`,
`listMonsterIds(cursor?,limit?) -> ids,nextCursor`, `presence(...)`, queue/leases.
All persistent profile writes use atomic updates, never save stale cached copies.
Service exposes `storage`, `clock`, and `profiles` only as convenience, not authority.
Clock `now()` returns absolute seconds; simulation may advance it.
Gameplay service `new(voyages,world)` and `handle(player,action,payload)` covers
activities/shop/settings/equip/requests and uses atomic profile updates.
Bootstrap owns validation, rate limits, PlayerAdded/Removing, update polling,
world refresh, and development-only controls.

All IDs and balance/unlock values are from shared Catalog/Config. No invented
external assets. Simulation is enabled only in Studio by server configuration.

Snapshot enrichment preserves the core daily reward counters as
`profile.rewardLimits`; `profile.daily` contains the three rotating request
cards. `profile.pendingEggs` reports recoverable accepted eggs without exposing
internal pending-operation contents. Shop buys use prefixed IDs (`decor:planter`);
placement and style requests use canonical asset IDs (`planter`, `coral`).
The complete durable schema, recovery algorithm and retention are in STORAGE.md.
