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

    Match_SteamID[i] = player_steam_id;
  }

  return Match_SteamID;
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
    if(StrEqual(Match_SteamID[i], steam_id)){
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
public SetPlayerData(Handle:database, int client, const char[] steam_id)
{
  DBResultSet teamQuery;
  char query[256];
  int TeamID;
  int PlayerIndex = -1;

  Format(query,sizeof(query), "SELECT `team_id`,`player_index` FROM `teams` WHERE player_id = (SELECT `id` FROM `players` WHERE `steamId` = '%s'); ", steam_id);
  teamQuery = SQL_Query(database, query);

  if(teamQuery == null || !SQL_FetchRow(teamQuery)){
    SetFailState("Can't fetch `team_id` from `teams` using player `steamId` = %s", steam_id);
  }

  TeamID = SQL_FetchInt(teamQuery, 0);
  PlayerIndex = SQL_FetchInt(teamQuery, 1) - 1;
  PrintToServer("PlayerIndex = %i", PlayerIndex);
  if(TeamID < 2){
    SetFailState("Team ID can't be below 2");	
  }

  if(PlayerIndex == -1){
    SetFailState("PlayerIndex must be equal or above 0"); 
  }

  Players_TeamID[client] = TeamID;
  Players_Indexes[client] = PlayerIndex;
  Players_BelongsToTeam[TeamID-2][PlayerIndex] = client;
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

  Player_Name[client] = real_nickname;

  GetClientName(client, current_nickname, sizeof(current_nickname));

  if(!StrEqual(real_nickname, current_nickname)){
    SetClientInfo(client, "name", real_nickname);

    if(DEBUG){ PrintToServer("[DB] (%s) > Switch nickname from '%s' to '%s'", steam_id, current_nickname, real_nickname);} //Debug info
  }
}

stock SetWarmupTime(int time)
{
    SetConVarInt(cvar_mp_warmuptime, time);
}

stock Action:StartWarmup(Handle timer)
{
    ServerCommand("mp_warmup_start");
}

stock Action:EndWarmup(Handle timer)
{
  ServerCommand("mp_warmup_end");
}

stock bool:IsWarmup()
{
  if (GameRules_GetProp("m_bWarmupPeriod") == 0) {
      return false;
  }
  return true;
}

/*********************************************************
 *  Equip the specified client with the knife
 * 
 * @noreturn
 *********************************************************/

stock CS_EquipKnife(client)
{
  ClientCommand(client, "slot3");
}

/*********************************************************
 *  strip all weapons from specified client but the knife
 * 
 * @noreturn
 *********************************************************/
stock SetKnifeOnly(client, bool:equip=true)
{
  if (!IsClientInGame(client) || GetClientTeam(client) <= 1) {
    return false;
  }
  
  new item_index;

  for (new i = 0; i < 5; i++){
    if (i == 2){ continue; }
    if ((item_index = GetPlayerWeaponSlot(client, i)) != -1){
      RemovePlayerItem(client, item_index);
    }
    if (equip){
      CS_EquipKnife(client);
    }
  }
  return true;
}

public StartKnifeRound()
{   
    for (new i = 1; i <= PLAYERSCOUNT; i++)
    {
      if (IsClientInGame(i) && GetClientTeam(i) > 1)
      {
        SetKnifeOnly(i);
      }
    }

    UpdateMatchStatus(db, MatchID, "knife");

    PrintToChatAll(" \x01[GLeague.io] > \x01\x0B\x04 %t", "KnifeRoundStarts");
    if(DEBUG){PrintToServer("[Knife round] initialized");} //Debug info
}

/*********************************************************
 *  get the team index opposite to the specified team
 * 
 * @param  team   team index to get opposite of
 * @return    false on error
 *      team index
 *********************************************************/
stock GetOtherTeam(team)
{
  if (team == 2) {return 3;}
  else if (team == 3){return 2;}
  else {return false;}
}

/*********************************************************
 *  swap all players to the opposite team
 *  allows for skin choice
 * 
 * @noreturn
 *********************************************************/
stock SwapTeams()
{
  new max_clients = GetMaxClients();
  new Handle:Datapack;
  for (new i = 1; i <= max_clients; i++){
    if (IsClientInGame(i) && !IsFakeClient(i) && Players_TeamID[i] > 1){
      CreateDataTimer(1.0, AssignPlayerTeam, Datapack);
      WritePackCell(Datapack, i);
      WritePackCell(Datapack, GetOtherTeam(Players_TeamID[i]));
    }

    if(IsClientInGame(i) && IsFakeClient(i)){
      CreateDataTimer(1.0, AssignPlayerTeam, Datapack);
      WritePackCell(Datapack, i);
      WritePackCell(Datapack, GetOtherTeam(GetClientTeam(i)));  
    }
  }
}

/*********************************************************
 *  swap team names
 * 
 * @noreturn
 *********************************************************/
stock SwitchTeamNames()
{
    char Tname[64], CTname[64];
    GetConVarString(cvar_team_name[0], CTname, sizeof(CTname));
    GetConVarString(cvar_team_name[1], Tname, sizeof(Tname));
    SetConVarString(cvar_team_name[0], Tname);
    SetConVarString(cvar_team_name[1], CTname);
}

/*********************************************************
 *  change match state
 * 
 * @param  state  MatchState
 * @noreturn
 *********************************************************/
stock ChangeState(MatchState state)
{
  if(DEBUG){PrintToServer("[Match State] > Changed from %d -> %d", enum_MatchState, state);} //Debug info
  enum_MatchState = state;
}

stock MakeRestart()
{
  SetConVarInt(cvar_mp_restartgame, 1);
}