/*********************************************************
 *  prints to server's console all player's steam ids
 * 
 * @param  SteamIDsArray	the integer to convert
 * @noreturn
 *********************************************************/
stock ShowPlayersSteamIDs(String:players[PLAYERSCOUNT][32])
{
	PrintToServer("---------- Players Steam IDs ----------");
	for(int i = 0; i <= PLAYERSCOUNT - 1; i++){
		PrintToServer("> [%i] %s", i, players[i]);
	}
	PrintToServer("---------------------------------------");
}

/*********************************************************
 *  set match id from command line
 * 
 * @param  SteamIDsArray	strings array
 * @return Match IDs 		integer
 *********************************************************/
stock SetMatchID()
{
	MatchID = GetCommandLineParamInt("match_id", -1);
	if(MatchID == -1)
	{
	  SetFailState("Can't fetch matchId from commandline");
	}

	return MatchID;
}

/*********************************************************
 *  select players steam ids from database and store it
 * 
 * @param  Database			database handle
 * @param  MatchID			integer
 * @return PlayersSteamIDs 	strings array
 *********************************************************/
stock String:GetMatchSteamIDs()
{
	DBResultSet teamsQuery, playersQuery;
	char query[256], player_steam_id[32];
	int player_id;

	Format(query,sizeof(query), "SELECT `player_id` FROM `teams` WHERE `match_id` = '%i'", MatchID);
	teamsQuery = SQL_Query(db, query);
	if(teamsQuery == null){
		SetFailState("Can't fetch data from `teams` where `match_id` = %i", MatchID);
	}

	for(int i = 0; i <= PLAYERSCOUNT - 1; i++){
		if(!SQL_FetchRow(teamsQuery)){
			SetFailState("Can't fetch row %i from `teams`", i);
		}

		player_id = SQL_FetchInt(teamsQuery, 0);

		Format(query,sizeof(query), "SELECT `steamId` FROM `players` WHERE `id` = '%i'", player_id);
		playersQuery = SQL_Query(db, query);

		if(playersQuery == null){
    	SetFailState("Can't fetch data from `players` where `id` = %i", MatchID);
    }

		if(!SQL_FetchRow(playersQuery)){
			SetFailState("Can't fetch row from `players` where `id` = ", player_id);
		}

		if(!SQL_FetchString(playersQuery, 0, player_steam_id, sizeof(player_steam_id))){
			SetFailState("Can't fetch steam_id string from `players` where `id` = ", player_id);
		}

		Match_SteamIDs[i] = player_steam_id;
  }

	return Match_SteamIDs;
}

/*********************************************************
 *  find steam id in global list of players steam ids
 * 
 * @param  SteamID			string
 * @return true or false on error 
 *********************************************************/
public bool:FindSteamID(const char[] steam_id)
{
	for(int i = 0; i <= PLAYERSCOUNT - 1; i++)
	{
		if(StrEqual(Match_SteamIDs[i], steam_id)){
			return true;
		}
	}

	return false;
}

/*********************************************************
 *  find player's team id by steam id
 * 
 * @param  Database			database handle
 * @param  SteamID			string
 * @return TeamID 			integer
 *********************************************************/
public GetPlayerTeamID(Handle:database, const char[] steam_id)
{
	DBResultSet teamQuery;
	char query[256];
	int team_id;

	Format(query,sizeof(query), "SELECT `team_id` FROM `teams` WHERE player_id = (SELECT `id` FROM `players` WHERE `steamId` = '%s'); ", steam_id);
	teamQuery = SQL_Query(database, query);

	if(teamQuery == null || !SQL_FetchRow(teamQuery)){
		SetFailState("Can't fetch `team_id` from `teams` using player `steamId` = %s", steam_id);
	}

	team_id = SQL_FetchInt(teamQuery, 0);
	if(team_id < 2){
		SetFailState("Team ID can't be below 2");	
	}

	return team_id;
}

/*********************************************************
 *  assign player to specificteam_id
 * 
 * @param  Timer			timer handle
 * @param  Datapack			datapack handle
 * @noreturn
 *********************************************************/
public Action:AssignPlayerTeam(Handle:timer, Handle:datapack)
{
	int client, team_id;

	ResetPack(datapack);
	client = ReadPackCell(datapack);
	team_id = ReadPackCell(datapack);

	ChangeClientTeam(client, team_id);
	CreateTimer(0.5, RespawnPlayer, client);
}

/*********************************************************
 *  respawn player
 * 
 * @param  Timer			timer handle
 * @param  Client			integer
 * @noreturn
 *********************************************************/
public Action:RespawnPlayer(Handle:timer, int client)
{
  CS_RespawnPlayer(client);
}

/*********************************************************
 *  set client name from database if differs with current
 *
 * @param  Database			timer handle
 * @param  Client			integer
 * @param  SteamID			string
 * @noreturn
 *********************************************************/
stock SetPlayerName(Handle:database, int client, const char[] steam_id)
{
	DBResultSet nameQuery;
	char query[256], real_nickname[32], current_nickname[32];
	Format(query,sizeof(query), "SELECT `nickname` FROM `players` WHERE `steamId` = '%s'", steam_id);
	nameQuery = SQL_Query(database, query);

	if(nameQuery == null || !SQL_FetchRow(nameQuery)){
		SetFailState("Can't fetch `nickname` from `players` where `steamId` = '%s'", steam_id);
	}

	if(!SQL_FetchString(nameQuery, 0, real_nickname, sizeof(real_nickname))){
		SetFailState("Can't fetch String `nickname` from `players` where `steamId` = '%s'", steam_id);		
	}

	Players_Names[client] = real_nickname;
	
	GetClientName(client, current_nickname, sizeof(current_nickname));

	if(!StrEqual(real_nickname, current_nickname)){
		SetClientInfo(client, "name", real_nickname);

		if(DEBUG){ PrintToServer("[DB] (%s) > Switch nickname from '%s' to '%s'", steam_id, current_nickname, real_nickname);} //Debug info
	}

}