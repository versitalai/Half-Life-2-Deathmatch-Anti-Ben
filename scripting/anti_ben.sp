/**
 * Anti-Ben: blocks gravity gun grenade pickups in Half-Life 2: Deathmatch.
 *
 * - Holding an npc_grenade_frag with weapon_physcannon is detected each usercmd
 *   via the networked m_hAttachedObject netprop.
 * - The physcannon is forced to drop it by injecting a fresh IN_ATTACK2 press
 *   (right click while holding = drop), then right click is suppressed until
 *   the player physically releases it, so the cannon can't instantly re-grab.
 * - The grenade's thrower and fuse are rolled back to their pre-pickup values,
 *   since HL2MP's CGrenadeFrag::OnPhysGunPickup steals ownership and resets the fuse.
 * - Punting (left click on a grenade NOT being held) is untouched.
 * - Every other prop is untouched: only npc_grenade_frag is checked.
 */

#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

#define GRENADE_CLASS   "npc_grenade_frag"
#define PHYSCANNON_CLASS "weapon_physcannon"

public Plugin myinfo =
{
	name = "Anti-Ben (No Gravity Gun Grenade Pickup)",
	author = "versitalai",
	description = "Prevents picking up frag grenades with the gravity gun; punting still allowed",
	version = PLUGIN_VERSION,
	url = "https://github.com/versitalai/half-life-2-deathmatch-anti-ben"
};

ConVar g_cvEnabled;
ConVar g_cvAnnounce;
ConVar g_cvAnnounceCooldown;
ConVar g_cvRestoreGrenade;
ConVar g_cvKillFallback;

// Per-client force-drop state
bool  g_bForcingDrop[MAXPLAYERS + 1];
bool  g_bPressNextCmd[MAXPLAYERS + 1];
bool  g_bBlockAttack2[MAXPLAYERS + 1];
float g_fForceDropStart[MAXPLAYERS + 1];
float g_fLastAnnounce[MAXPLAYERS + 1];

// Per-grenade snapshot taken while nobody holds it (indexed by entity index)
int   g_iNadeRef[2049];
int   g_iNadeThrower[2049];   // entity reference of thrower, or INVALID_ENT_REFERENCE
float g_fNadeDetonate[2049];

public void OnPluginStart()
{
	CreateConVar("sm_antiben_version", PLUGIN_VERSION, "Anti-Ben plugin version",
		FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY);
	g_cvEnabled          = CreateConVar("sm_antiben_enabled", "1", "Block gravity gun grenade pickups", _, true, 0.0, true, 1.0);
	g_cvAnnounce         = CreateConVar("sm_antiben_announce", "1", "Announce offenders in public chat", _, true, 0.0, true, 1.0);
	g_cvAnnounceCooldown = CreateConVar("sm_antiben_announce_cooldown", "3.0", "Min seconds between announcements for the same player", _, true, 0.0);
	g_cvRestoreGrenade   = CreateConVar("sm_antiben_restore", "1", "Restore grenade thrower and fuse to pre-pickup values", _, true, 0.0, true, 1.0);
	g_cvKillFallback     = CreateConVar("sm_antiben_kill_fallback", "1.0", "If still held after this many seconds, delete the grenade (0 = never)", _, true, 0.0);

	AutoExecConfig(true, "anti_ben");

	for (int i = 0; i < sizeof(g_iNadeRef); i++)
	{
		g_iNadeRef[i] = INVALID_ENT_REFERENCE;
	}
}

public void OnMapStart()
{
	// Game time restarts each map; stale timestamps would mute announcements
	for (int client = 1; client <= MaxClients; client++)
	{
		ResetClient(client);
		g_fLastAnnounce[client] = 0.0;
	}
}

public void OnClientDisconnect(int client)
{
	ResetClient(client);
	g_fLastAnnounce[client] = 0.0;
}

void ResetClient(int client)
{
	g_bForcingDrop[client] = false;
	g_bPressNextCmd[client] = false;
	g_bBlockAttack2[client] = false;
	g_fForceDropStart[client] = 0.0;
}

/**
 * Returns the grenade entity the client's gravity gun is holding, or -1.
 */
int GetHeldGrenade(int client)
{
	if (!IsPlayerAlive(client))
	{
		return -1;
	}

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return -1;
	}

	char cls[32];
	GetEntityClassname(weapon, cls, sizeof(cls));
	if (!StrEqual(cls, PHYSCANNON_CLASS))
	{
		return -1;
	}

	if (!HasEntProp(weapon, Prop_Send, "m_hAttachedObject"))
	{
		return -1;
	}

	int held = GetEntPropEnt(weapon, Prop_Send, "m_hAttachedObject");
	if (held <= MaxClients || !IsValidEntity(held))
	{
		return -1;
	}

	GetEntityClassname(held, cls, sizeof(cls));
	return StrEqual(cls, GRENADE_CLASS) ? held : -1;
}

bool IsGrenadeHeldByAnyone(int grenade)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetHeldGrenade(client) == grenade)
		{
			return true;
		}
	}
	return false;
}

/**
 * Snapshot thrower + fuse of every free grenade so a pickup can be rolled back.
 * Punts also change these, but the snapshot catches up next frame, so punt
 * ownership is kept.
 */
public void OnGameFrame()
{
	if (!g_cvEnabled.BoolValue || !g_cvRestoreGrenade.BoolValue)
	{
		return;
	}

	int grenade = -1;
	while ((grenade = FindEntityByClassname(grenade, GRENADE_CLASS)) != -1)
	{
		if (grenade >= sizeof(g_iNadeRef) || IsGrenadeHeldByAnyone(grenade))
		{
			continue;
		}

		g_iNadeRef[grenade] = EntIndexToEntRef(grenade);
		int thrower = GetEntPropEnt(grenade, Prop_Data, "m_hThrower");
		g_iNadeThrower[grenade] = (thrower != -1) ? EntIndexToEntRef(thrower) : INVALID_ENT_REFERENCE;
		g_fNadeDetonate[grenade] = GetEntPropFloat(grenade, Prop_Data, "m_flDetonateTime");
	}
}

void RestoreGrenade(int grenade)
{
	if (!g_cvRestoreGrenade.BoolValue || grenade >= sizeof(g_iNadeRef))
	{
		return;
	}

	// Snapshot must belong to this exact entity, not a recycled index
	if (g_iNadeRef[grenade] != EntIndexToEntRef(grenade))
	{
		return;
	}

	int thrower = EntRefToEntIndex(g_iNadeThrower[grenade]);
	SetEntPropEnt(grenade, Prop_Data, "m_hThrower", (thrower != INVALID_ENT_REFERENCE) ? thrower : -1);
	SetEntPropFloat(grenade, Prop_Data, "m_flDetonateTime", g_fNadeDetonate[grenade]);
}

void Announce(int client)
{
	if (!g_cvAnnounce.BoolValue)
	{
		return;
	}

	float now = GetGameTime();
	if (g_fLastAnnounce[client] > 0.0 && now - g_fLastAnnounce[client] < g_cvAnnounceCooldown.FloatValue)
	{
		return;
	}
	g_fLastAnnounce[client] = now;

	PrintToChatAll("%N is a chud and used the banned grenade strat", client);
	LogMessage("%L picked up a frag grenade with the gravity gun", client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int grenade = GetHeldGrenade(client);

	if (grenade != -1)
	{
		if (!g_bForcingDrop[client])
		{
			// First tick we see it held
			g_bForcingDrop[client] = true;
			g_bPressNextCmd[client] = false;
			g_bBlockAttack2[client] = true;
			g_fForceDropStart[client] = GetGameTime();

			RestoreGrenade(grenade);
			Announce(client);
		}

		float killAfter = g_cvKillFallback.FloatValue;
		if (killAfter > 0.0 && GetGameTime() - g_fForceDropStart[client] >= killAfter)
		{
			// Physcannon detaches cleanly when its held entity is removed
			AcceptEntityInput(grenade, "Kill");
		}

		// Alternate release/press so the cannon sees a new IN_ATTACK2 press edge
		// -> CWeaponPhysCannon drops the held object. Repeats until it lets go
		// (covers the post-pickup m_flNextSecondaryAttack delay).
		if (g_bPressNextCmd[client])
		{
			buttons |= IN_ATTACK2;
		}
		else
		{
			buttons &= ~IN_ATTACK2;
		}
		g_bPressNextCmd[client] = !g_bPressNextCmd[client];

		// Stop a punt-while-held (left click launches held objects)
		buttons &= ~IN_ATTACK;
		return Plugin_Changed;
	}

	g_bForcingDrop[client] = false;

	if (g_bBlockAttack2[client])
	{
		if (buttons & IN_ATTACK2)
		{
			// Still physically holding right click: don't let the cannon
			// pull the grenade straight back in
			buttons &= ~IN_ATTACK2;
			return Plugin_Changed;
		}
		g_bBlockAttack2[client] = false;
	}

	return Plugin_Continue;
}
