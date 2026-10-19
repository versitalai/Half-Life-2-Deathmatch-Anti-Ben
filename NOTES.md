# Developer Notes

Reference for maintainers (human or AI). Update the changelog section on every change.

## Layout

- `scripting/anti_ben.sp` — the whole plugin.
- `README.md` — user-facing install + convars.
- `NOTES.md` — this file: internals, decisions, test plan, changelog.

## How it works

### Detection
`weapon_physcannon` networks `m_hAttachedObject` (EHANDLE of the held entity) so the client can predict the held object. Plugin reads it in `OnPlayerRunCmd` for the player's active weapon. If the held entity classname is `npc_grenade_frag` → violation.

Why not block before pickup? Engine flag `EFL_NO_PHYSCANNON_INTERACTION` (1<<30) stops pickup, but per the SDK it also stops punting — conflicts with the "punt still allowed" requirement. Also gives no "detected" moment for the chat message.

### Forced drop
HL2 gravity gun is toggle: right-click while holding = drop (`CWeaponPhysCannon::SecondaryAttack` checks `m_afButtonPressed & IN_ATTACK2`). `m_afButtonPressed` is derived from the change in `buttons` between usercmds, so the plugin alternates stripping / adding `IN_ATTACK2` each cmd to manufacture a press edge. Repeats until the cannon lets go (covers any post-pickup attack delay).

After the drop, `IN_ATTACK2` stays stripped until the player physically releases right-click. Without this, holding right-click makes the cannon pull + re-grab the grenade the next tick (loop).

`IN_ATTACK` is also stripped while held: left-click while holding = launch, which is the strat itself.

### Fallback
If still held after `sm_antiben_kill_fallback` seconds, grenade is removed. Physcannon handles held-entity removal cleanly (attached handle goes NULL → `DetachObject`).

### Owner/fuse rollback
HL2MP `CGrenadeFrag::OnPhysGunPickup` sets thrower = picker and resets fuse to grace time. `OnGameFrame` snapshots `m_hThrower` and `m_flDetonateTime` (datamap) of every grenade nobody is holding; first detection writes the snapshot back. Snapshot validated by entity reference so recycled indexes don't get stale data. Punts also change thrower/fuse — snapshot catches up next frame, so punt ownership is kept.

## Known limits / ideas

- Grenade can sit in the gun for a few ticks (~1–30ms typical, ≤0.5s worst) before drop.
- Players also lose right-click for other props until they release the button after a violation. Intentional.
- Only `npc_grenade_frag`. Add classnames (e.g. `grenade_ar2`) if needed — single `#define`.
- Not verified on a live server from this repo yet. See test plan.
- Possible: punishments (slay, kick after N strikes), admin immunity flag, translation file for message.

## Test plan (live server)

1. Throw frag, right-click it with grav gun → message in chat, grenade drops, explodes on original fuse, kill credited to thrower.
2. Hold right-click continuously on a grenade → caught once, no re-grab, no chat spam (cooldown).
3. Left-click a grenade on the ground → punts normally, no message.
4. Pick up / punt barrels, crates, combine balls → unaffected.
5. Right-click a prop right after a violation while still holding the button → nothing until release (expected).
6. `sm_antiben_enabled 0` → vanilla behavior.

## Changelog

- **1.0.0** — Initial plugin: detection via `m_hAttachedObject`, forced drop via IN_ATTACK2 injection, re-grab block, owner/fuse rollback, kill fallback, chat call-out with cooldown.
