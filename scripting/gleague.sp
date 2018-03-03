#pragma semicolon 1

#define PLAYERSCOUNT 2
#define DEFAULT_LANGUAGE 22
#define VERSION "0.0.1prealpha"

/* include assist scripts */
#include <sourcemod>
#include <cstrike>
#include <sdktools>

/* debug */
new bool:DEBUG = true;

/* database handler */
new Handle:db = INVALID_HANDLE;

/* set default match id */
int match_id = -1;

/* players data storage */
new String:players_steam_ids[PLAYERSCOUNT][32];
new String:players_names[PLAYERSCOUNT][32];

/* flags */
bool flag_warmup = true; 				//warmup
bool flag_live = false; 				//match live
bool flag_knife_round = false; 			//knife round
bool flag_knife_round_started = false; 	//knife round started
bool flag_all_connected = false; 		//all connected

/* include gleague additional functions */
#include <gleague>


/*********************************************************
 *  plugin description
 *********************************************************/
public Plugin myinfo =
{
    name = "GLeague MM",
    author = "Stanislav 'glmn' Gelman",
    description = "An additional cs:go matchmaking system with own rankings by 'glmn'. From Russian to Russians w/ love :)",
    version = VERSION,
    url = "http://gleague.io/"
};

/*********************************************************
 *  event fire when plugin start
 *********************************************************/
public OnPluginStart()
{
	LoadTranslations("gleague.phrases.txt");

	/* Event hooks */
	HookEvent("player_connect_full", Event_Player_Full_Connect, EventHookMode_Post);
	HookEvent("player_changename", Event_Player_Name);
	HookEvent("player_team", Event_Player_Team);

	/* Init MySQL connection and fill variables with data */
	MySQL_Connect();
	SetMatchID();
	GetPlayersSteamIDs(db, match_id);

	if(DEBUG){ShowPlayersSteamIDs(players_steam_ids);} //Debug info

	UpdateMatchStatus(db, match_id, "ready");

}

/*********************************************************
 *  event fire when client set his steam id
 * 
 * @param  Client			database handle
 * @param  SteamID			string
 * @noreturn
 *********************************************************/
public OnClientAuthorized(int client, const char[] steam_id)
{
	if(IsFakeClient(client)) {return;}

	SetClientLanguage(client, DEFAULT_LANGUAGE);

	if(DEBUG){PrintToServer("[Steam ID] > %s", steam_id);} //Debug info

	if(!FindSteamID(steam_id)){
        KickClient(client, "%t", "NoAccess");
	}
}

/*********************************************************
 *  event fire when player fully connected to server
 * 
 * @param  Event			event handle
 * @param  Name				string
 * @param  Broadcast		boolean
 * @noreturn
 *********************************************************/
public Action:Event_Player_Full_Connect(Handle:event, const String:name[], bool:dontBroadcast)
{
	char steam_id[256];
	int team_id;
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	new Handle:datapack;

	if(IsFakeClient(client)) {return;}
	GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id));

	if(DEBUG){PrintToServer("[Event] (%s) > Event_Player_Full_Connect", steam_id);} //Debug info

	SetPlayerName(db, client, steam_id);

	team_id = GetPlayerTeamID(db, steam_id);

	CreateDataTimer(1.0, AssignPlayerTeam, datapack);
	WritePackCell(datapack, client);
	WritePackCell(datapack, team_id);

	if(DEBUG){ PrintToServer("[Team ID] (%s) > %i",steam_id, team_id); } //Debug info

	UpdatePlayerStatus(db, match_id, steam_id, "connected");
	if(DEBUG){PrintToServer("[DB] (%s) > UpdatePlayerStatus > connected", steam_id);} //Debug info
}

/*********************************************************
 *  event fire when player want to change his name
 * 
 * @param  Event			event handle
 * @param  Name				string
 * @param  Broadcast		boolean
 * @noreturn
 *********************************************************/
public Event_Player_Name(Handle:event, const String:name[], bool:dontBroadcast)
{
	char steam_id[256];
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(IsFakeClient(client)) {return;}

	GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id));
	SetPlayerName(db, client, steam_id);
}

/*********************************************************
 *  event fire when player want to change team
 * 
 * @param  Event			event handle
 * @param  Name				string
 * @param  Broadcast		boolean
 * @noreturn
 *********************************************************/
public Event_Player_Team(Handle:event, const String:name[], bool:dontBroadcast)
{
	char steam_id[256];
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	new Handle:datapack;

	if(IsFakeClient(client) || !IsClientInGame(client)){return;}

	GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id));

	new needle_team_id = GetPlayerTeamID(db, steam_id);
	new old_team_id = GetEventInt(event, "oldteam");
	new new_team_id = GetEventInt(event, "team");

	if(needle_team_id != new_team_id){
		CreateDataTimer(1.0, AssignPlayerTeam, datapack);
		WritePackCell(datapack, client);
		WritePackCell(datapack, needle_team_id);
	}

	
}

/*********************************************************
 *  event fire when player disconnect from server
 * @param  Client			integer
 * @noreturn
 *********************************************************/
public OnClientDisconnect(int client)
{
	char steam_id[256];
	if(IsFakeClient(client)) {return;}

	GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id));

	UpdatePlayerStatus(db, match_id, steam_id, "disconnected");
	if(DEBUG){PrintToServer("[DB] (%s)> UpdatePlayerStatus > disconnected",steam_id);} //Debug info
}