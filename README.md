# Half-Life-2-Deathmatch-Anti-Ben

SourceMod plugin for Half-Life 2: Deathmatch. Stops players picking up frag grenades with the gravity gun.

## Behavior

| Action | Result |
|---|---|
| Gravity gun right-click (pick up) on frag grenade | Blocked: grenade forced out of the gun, offender called out in chat |
| Gravity gun left-click (punt) on grenade lying on the ground | Allowed |
| Gravity gun pick up / punt any other prop | Allowed (only `npc_grenade_frag` is checked) |

Chat message on detection:

```
<player name> is a chud and used the banned grenade strat
```

The grenade's owner and fuse are rolled back to pre-pickup values, because HL2DM normally hands kill credit to the picker and resets the fuse to 1.5s on pickup.

## Install

1. Server needs [Metamod:Source](https://www.sourcemm.net/) + [SourceMod](https://www.sourcemod.net/) (1.11+).
2. Compile `scripting/anti_ben.sp` with your server's `spcomp` (or SourceMod's web compiler):
   ```
   spcomp scripting/anti_ben.sp -o anti_ben.smx
   ```
3. Copy `anti_ben.smx` to `hl2mp/addons/sourcemod/plugins/`.
4. `sm plugins load anti_ben` or change map.

Config auto-generated at `hl2mp/cfg/sourcemod/anti_ben.cfg` on first load.

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `sm_antiben_enabled` | `1` | Master switch |
| `sm_antiben_announce` | `1` | Post the chat call-out |
| `sm_antiben_announce_cooldown` | `3.0` | Min seconds between call-outs for the same player |
| `sm_antiben_restore` | `1` | Roll grenade owner + fuse back to pre-pickup values |
| `sm_antiben_kill_fallback` | `1.0` | Delete grenade if still held after N seconds (`0` = never) |

See [NOTES.md](NOTES.md) for how it works internally, known limits, and test plan.
