# MAIL A MONSTER

**Little monster. Big adventure. Send a smile.**

A Roblox postal adventure: hatch a little monster, help visiting monsters collect
souvenirs, launch voyages, and welcome your own monster home with a passport of
memories. Monsters remain permanently owned by their original owner.

## Open the game

Download `build/MailAMonster.rbxlx`, open it in **Roblox Studio**, and press **Play**.
The islands and locally generated assets appear when the server starts. The
default Studio backend displays **Studio simulation — progress is not saved**.
No plugins, purchased assets, API keys, or external models are needed to try it.

See [the import and publishing guide](docs/IMPORT.md) for exact steps, including
Rojo syncing and the private live-service test setup.

## First visit

1. Hatch your free egg and choose a curated name.
2. Open the mailbox, give the labeled NPC tutorial visitor a free souvenir, and
   fire the cannon.
3. Complete Parcel Sorting, Postal Flower Watering, or Floating Letter Collecting
   on your island to earn Postage.
4. Launch your own monster on the free **Practice Voyage**. Three fictional NPC
   postcards arrive over roughly 75 seconds.
5. View the homecoming, claim your welcome decoration, and explore normal voyages,
   your journal, daily requests, and the cosmetic shop.

The eight plots surround a shared post office. Activities remain available while
monsters travel. Every souvenir and every egg trait is cosmetic. Forwarding is
free, including after a courier reaches their daily reward limit.

## Build and checks

Python 3 and Internet access to official GitHub releases are needed for first-time
tool installation. Subsequent builds use the pinned local binaries.

```sh
python3 tools/setup.py
python3 tools/check.py
python3 tools/build.py
```

The source uses Rojo's standard service layout. Balance values, plans, activity
timings, and unlocks are centralized in `src/shared/Config.lua`; content IDs and
curated names live in `src/shared/Catalog.lua`.

## Persistence and verification

Studio simulation and live services implement the same storage interface. Live
servers use canonical DataStore records, temporary MemoryStore matching hints,
atomic profile updates, and recoverable reward operations. Published servers
cannot enable simulation from a client request. The default live namespace is
`MAM_TEST_V1`; use a separate private test universe for real-service testing.

There is no external background scheduler. If every game server is stopped,
voyages are reconciled when a server runs again. See [storage and recovery](docs/STORAGE.md).

[The test report](docs/TESTING.md) distinguishes automated logic checks from
Studio, mobile, eight-player, and real cross-server tests. This cloud workspace
cannot run Roblox Studio; a place build does not establish that those playtests
have passed.

All art is generated from Roblox primitives. Optional audio has no configured
asset IDs; visual cues work independently. Robux products are hidden and have no
configured products or purchase path. This project does not publish itself.
