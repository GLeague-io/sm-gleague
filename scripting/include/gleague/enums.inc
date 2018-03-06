enum MatchState {
  MatchState_None,							              // no setup has taken place
  MatchState_Warmup,                        	// setup done, waiting for players to ready up
  MatchState_KnifeRound,                    	// in the knife round
  MatchState_WaitingForKnifeRoundDecision,  	// waiting for a .stay/.swap command after the knife
  MatchState_GoingLive,                     	// in the lo3 process
  MatchState_Live,                          	// the match is live
};

MatchState enum_MatchState = MatchState_None;