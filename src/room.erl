-module(room).
-export([start/1]).
-export([enter/2, leave/2, play/2, get_state/1, observe/2]).
-export([reset/1]).

-define(ROOM_TIME_OUT, 60 * 10).

-record(state, {board,
				status = waiting, % status = waiting ! playing
				current_player = none,
				players = [], % players = [{pid, nick_name, monitor_ref}]
				observers = [],
				game_state,
				steps = []
				}).

%% APIs
start(Board) ->
	Pid = spawn(fun() -> init(Board) end),
	{ok, Pid}.

enter(Pid, {Player, NickName}) ->
	Pid ! {enter, Player, NickName}.

leave(Pid, Player) ->
	Pid ! {leave, Player}.

observe(Pid, {Observer, NickName}) ->
	Pid ! {observe, Observer, NickName}.	

play(Pid, {Player, Move}) ->
	Pid ! {play, Player, Move}.

get_state(Pid) ->
	call(Pid, get_state).	

reset(Pid) ->
	Pid ! reset.

call(Pid, Msg) ->
	Ref = make_ref(),
	Pid ! {Msg, Ref, self()},
	receive
		{Ref, Reply} ->
			Reply
	end.	

init(Board) ->
	<<A:32, B:32, C:32>> = crypto:rand_bytes(12),
	random:seed({A, B, C}),
	loop(#state{board = Board}).	

select_player(Players) ->
	N = random:uniform(2),
	{Pid, NickName, _} = lists:nth(N, Players),
	{Pid, NickName}.	

loop(State = #state{status = waiting, board = Board, players = Players, observers = Obs}) ->
	receive
		{enter, Pid, NickName} ->
			case Players of
				[] ->
					notify_user(Pid, greeting(NickName)),
					Ref = erlang:monitor(process, Pid),
					loop(State#state{players = [{Pid, NickName, Ref}]});
				[{Pid, _, _}] ->
					notify_user(Pid, greeting(NickName)),				
					loop(State);
				[{_Pid2, _, _}] ->
					notify_user(Pid, greeting(NickName)),
					Ref = erlang:monitor(process, Pid),
					NewPlayers = [{Pid, NickName, Ref} | Players],
					First = select_player(NewPlayers),
					GameState = Board:start(),
					self() ! begin_game,
					loop(State#state{status = playing,
									 game_state = GameState,
									 current_player = First,
									 players = NewPlayers})
			end;
		{leave, Pid} ->
			case lists:keyfind(Pid, 1, Players) of
				{Pid, _, Ref} ->
					NewPlayers = lists:keydelete(Pid, 1, Players),
					erlang:demonitor(Ref),
					loop(State#state{players=NewPlayers});
				false ->
					case lists:keyfind(Pid, 1, Obs) of
						{Pid, _, Ref} ->
							NewObs = lists:keydelete(Pid, 1, Obs),
							erlang:demonitor(Ref),
							loop(State#state{observers = NewObs});
						false ->
							loop(State)
					end
			end;
		{get_state, Ref, From} ->
			PlayerNickNames = [ NickName || {_Pid, NickName, _Ref} <- Players],
			From ! {Ref, {State#state.status, PlayerNickNames}},
			loop(State);
		reset ->
			loop(State#state{status=waiting,
				 players=[],
				 observers=[],
				 current_player=none});			

		{observe, Pid, NickName} ->
			notify_user(Pid, greeting(NickName)),		
			Ref = erlang:monitor(process, Pid),
			loop(State#state{observers = [{Pid, NickName, Ref} | Obs]});	

		{'DOWN', _, process, Pid, Reason} ->
			io:format("~p down @waiting for: ~p~n", [Pid, Reason]),
			self() ! {leave, Pid},
			loop(State);

		Unexpected ->
			io:format("unexpected @waiting ~p~n", [Unexpected]),
			loop(State)				
	end;
loop(State = #state{status = playing,
					current_player = {Current, CurrentNickName},
					players = Players,
					observers = Obs,
					board = Board,
					game_state = GameState, 
					steps = Steps}) ->
	receive 
		{enter, _Pid, _NickName} ->
			loop(State);
		{leave, Pid} ->
			case lists:keyfind(Pid, 1, Players) of
				{Pid, _NickName, Ref} ->
					NewPlayers = [{_Pid2, _NickName2, _}]
							   = lists:keydelete(Pid, 1, Players),
					erlang:demonitor(Ref),
					loop(State#state{status=waiting,
									 current_player = none,
									 players = NewPlayers});
				_ ->
					case lists:keyfind(Pid, 1, Obs) of
						{Pid, _, Ref} ->
							NewObs = lists:keydelete(Pid, 1, Obs),
							erlang:demonitor(Ref),
							loop(State#state{observers = NewObs});
						false ->
							loop(State)
					end
			end;

		{observe, Pid, NickName} ->
			notify_user(Pid, greeting(NickName)),		
			Ref = erlang:monitor(process, Pid),
			loop(State#state{observers = [{Pid, NickName, Ref} | Obs]});	

		show ->
			io:format("status=~p, current_player=~p, players=~p~n", [State#state.status, CurrentNickName, Players]),
			loop(State);
		begin_game ->
			{Next, NextNickName} = next_player(Current, Players),
			update(Current, GameState),
			update(Next, GameState),
			update(Obs, GameState),			
			play(Current),
			loop(State#state{steps = [{start, CurrentNickName, NextNickName}]});
		reset ->
			loop(State#state{status=waiting,
				 players=[],
				 observers=[],
				 current_player=none});
		{play, Current, Move} ->
			case Board:is_legal(GameState, Move) of
				false ->
					play(Current),
					loop(State);
				true ->
					GameState2 = Board:next_state(GameState, Move),
					NextPlayer = {Next, NextNickName} = next_player(Current, Players),
					update(Current, Move, GameState2),
					update(Next, Move, GameState2),
                    update(Obs, Move, GameState2),
					NewSteps = Steps ++ [{move, integer_to_list(Board:current_player(GameState)), Move}],
					case Board:winner(GameState2) of
						on_going ->
							play(Next),
							loop(State#state{game_state = GameState2,
											 current_player = NextPlayer,
											 steps=NewSteps});
						draw ->
							NewSteps2 = NewSteps ++ [{finish, draw}],
							store_data(NewSteps2),
							db_api:add_game(CurrentNickName, NextNickName, draw, NewSteps2),
							loop(State#state{status = waiting,
											 players=[],
											 current_player=none,
											 steps=[]});
						_ ->
							[notify_user(Pid, congradulations(CurrentNickName)) || {Pid, _, _} <- Players],
							NewSteps2 = NewSteps ++ [{finish, winner, integer_to_list(Board:current_player(GameState))}], 
							store_data(NewSteps2),
							db_api:add_game(CurrentNickName, NextNickName, CurrentNickName, NewSteps2),
							loop(State#state{status=waiting,
											 players=[],
											 current_player=none,
											 steps=[]})
					end
			end;	
		{get_state, Ref, From} ->
			PlayerNickName = [ NickName || {_Pid, NickName, _Ref} <- Players],
			From ! {Ref, {State#state.status, PlayerNickName}},
			loop(State);				
		{'DOWN', _, process, Pid, Reason} ->
			io:format("~p down @waiting for: ~p~n", [Pid, Reason]),
			self() ! {leave, Pid},
			loop(State);
		Unexpected ->
			io:format("unexpected @waiting ~p~n", [Unexpected]),
			loop(State)
	    after ?ROOM_TIME_OUT * 1000 ->    
	        exit(time_out)			
	end.


next_player(Pid, [{Pid, _, _}, {Pid2, NickName, _}]) ->
	{Pid2, NickName};
next_player(Pid, [{Pid2, NickName, _}, {Pid, _, _}]) ->
	{Pid2, NickName}.

update(Obs, GameState) when is_list(Obs) ->
	[Pid ! {update, none, GameState} || {Pid, _, _} <- Obs];

update(Pid, GameState) ->
	Pid ! {update, none, GameState}.

update(Obs, Move, GameState) when is_list(Obs) ->
	[Pid ! {update, Move, GameState} || {Pid, _, _} <- Obs];

update(Pid, Move, GameState) ->
	Pid ! {update, Move, GameState}.

play(Pid) ->
	Pid ! play.

notify_user(Pid, Msg) ->
	Pid ! {notify, Msg}.	

greeting(NickName) ->
	"welcome " ++ NickName.

congradulations(NickName) ->
	NickName ++ " Wins!!!".

store_data(Steps) ->
	{ok, CurrentDir} = file:get_cwd(),
	make_dir(),
	{ok, LogFile} = file:open(make_filename(), [append]),	
	[store_data(Step, LogFile) || Step <- Steps],
	file:close(LogFile),
	file:set_cwd(CurrentDir).

store_data({start, CurrentNickName, NextNickName}, LogFile) ->	
	io:format(LogFile, "{\"begin\":[~p,~p]}~n", [CurrentNickName, NextNickName]);
store_data({move, Player, {R, C, R1, C1}}, LogFile) ->
	io:format(LogFile, "{~p:[~p,~p,~p,~p]}~n", [Player, R, C, R1, C1]);
store_data({finish, draw}, LogFile) ->	
	io:format(LogFile, "{~p:~p}~n", ["end", "draw"]);
store_data({finish, winner, Player}, LogFile) ->	
	io:format(LogFile, "{~p:~p}~n", ["end", Player]).

make_dir() ->
	DataDir = "play_data",
	file:make_dir(DataDir),
	file:set_cwd(DataDir),
	{Year, Month, Day} = date(),	 
	Dir = io_lib:format("~p_~p_~p", [Year, Month, Day]),
	file:make_dir(Dir),
	file:set_cwd(Dir).

make_filename() ->
	{MegaSecs, Secs, MicroSecs} = now(),
	io_lib:format("~p_~p_~p_~p.txt", [MegaSecs, Secs, MicroSecs, random:uniform(100)]).


