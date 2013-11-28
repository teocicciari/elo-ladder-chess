(* helpers *)

let replace n p l =
	let l = List.remove_assoc n l in
	(n, p) :: l

let (|>) x f = f x

type date = {
	day: int;
	month: int;
	year: int;
}

let date_of_string d =
	let r = Re_perl.re "(\\d*)/(\\d*)/(\\d*)" |> Re.compile in
	let m = Re.exec r d in
	{
		day = Re.get m 1 |> int_of_string;
		month = Re.get m 2 |> int_of_string;
		year = Re.get m 3 |> int_of_string;
	}

let string_of_date {day; month; year} =
	Printf.sprintf "%02d/%02d/%04d" day month year

(* Elo rating calculations *)

let k = 32.

let get_factor rating =
	10. ** (rating /. 400.)

let get_expectation rating1 rating2 =
	let factor1 = get_factor rating1 in
	let factor2 = get_factor rating2 in
	factor1 /. (factor1 +. factor2)

let get_updates rating1 rating2 result =
	let expectation = get_expectation rating1 rating2 in
	let update = k *. (result -. expectation) in
	rating1 +. update,
	rating2 -. update

(* ladder *)

type player = {
	name: string;
	rating: float;
	game_count: int;
}

let strings_of_ladder players =
	let sorted = 
		List.sort (fun (_, {rating=rating1}) (_, {rating=rating2}) ->
			compare rating2 rating1)
		players
	in
	let lines =
		List.mapi (fun rank (_, p) ->
			Printf.sprintf "%2d.  %-30s  %4d  (%d)" (succ rank) p.name
				(int_of_float p.rating) p.game_count;
		) sorted
	in
	lines

let play' player1 player2 result =
	let update1, update2 = get_updates player1.rating player2.rating result in
	{player1 with rating = update1; game_count = player1.game_count + 1},
	{player2 with rating = update2; game_count = player2.game_count + 1}

let string_of_result = function
	| 1. -> "  1 - 0"
	| 0.5 -> "0.5 - 0.5"
	| _ -> "  0 - 1"

let strings_of_games players games =
	let lines =
		List.map (fun (date, nick1, nick2, result) ->
			let player1 = List.assoc nick1 players in
			let player2 = List.assoc nick2 players in
			Printf.sprintf "%s   %20s - %-20s    %s" (string_of_date date) player1.name player2.name
				(string_of_result result)
		) (List.rev games)
	in
	lines

let play players nick1 nick2 result =
	let player1 = List.assoc nick1 players in
	let player2 = List.assoc nick2 players in
	let player1, player2 = play' player1 player2 result in
	players |> replace nick1 player1 |> replace nick2 player2

let play_games players games =
	List.fold_left (fun players (date, nick1, nick2, result) ->
		play players nick1 nick2 result
	) players games

(* filing *)

let read_players fname =
	let f = open_in fname in
	let parse s =
		let r = Re_str.regexp_string "," in
		let split = Re_str.split_delim r s in
		match split with
		| nick :: name :: rating :: _ ->
			let rating = rating |> int_of_string |> float_of_int in
			nick, {name; rating; game_count = 0}
		| _ -> failwith "parser error"
	in
	let players = ref [] in
	begin
		try
			while true do
				let s = input_line f in
				players := parse s :: !players
			done
		with End_of_file -> ()
	end;
	close_in f;
	!players

let read_games fname =
	let f = open_in fname in
	let parse s =
		let r = Re_str.regexp_string "," in
		let split = Re_str.split_delim r s in
		match split with
		| date :: nick1 :: nick2 :: result :: _ ->
			date_of_string date, nick1, nick2, float_of_string result
		| _ -> failwith "parser error"
	in
	let games = ref [] in
	begin
		try
			while true do
				let s = input_line f in
				games := parse s :: !games
			done
		with End_of_file -> ()
	end;
	close_in f;
	List.rev !games

let string_of_yaml_header () =
	Printf.sprintf "%s\n%s\n%s" "---" "layout: default" "---"

let string_of_title ?(gh_pages = false) title =
	if gh_pages
	then Printf.sprintf "# %s" title
	else Printf.sprintf "\n%s\n%s" title (String.make (String.length title) '=')

let string_of_heading ?(gh_pages = false) heading =
	if gh_pages
	then Printf.sprintf "### %s" heading
	else Printf.sprintf "\n%s\n%s" heading (String.make (String.length heading) '-')

let string_of_section lines =
	let lines = List.map (fun line -> "    " ^ line) lines in
	String.concat "\n" lines

let print_summary title players_path games_path gh_pages =
	let players = read_players players_path in
	let games = read_games games_path in

	if gh_pages then print_endline (string_of_yaml_header ());

	begin match title with
	| Some text -> print_endline (string_of_title ~gh_pages text)
	| None -> ()
	end;

	print_endline (string_of_heading ~gh_pages "Ladder");
	print_endline (string_of_section (strings_of_ladder (play_games players games)));

	print_endline (string_of_heading ~gh_pages "Games");
	print_endline (string_of_section (strings_of_games players games));
	()

(* Command line interface *)

open Cmdliner

let title =
	let doc = "Optionally print a title before printing the ladder." in
	Arg.(value & opt (some string) None & info ["t"; "title"] ~docv:"TITLE" ~doc)
	
let players_path =
	let doc = "Path to players file. See $(i,FILE-FORMATS) for details." in
	Arg.(required & pos 0 (some file) None & info [] ~docv:"PLAYERS" ~doc)

let games_path =
	let doc = "Path to games file. See $(i,FILE-FORMATS) for details." in
	Arg.(required & pos 1 (some file) None & info [] ~docv:"GAMES" ~doc)

let gh_pages =
	let doc = "Output markdown for Github pages publication of ladder." in
	Arg.(value & flag & info ["gh-pages"] ~doc)

let cmd =
	let doc = "Compute and print ELO ladder" in
	let man = [
		`S "DESCRIPTION";
			`P "$(tname) computes the resulting ELO ratings for the players
			    specified in $(i,PLAYERS) after playing the games specified in
			    $(i,GAMES).";
		`S "FILE-FORMATS";
			`P "The $(i,PLAYERS) file should be in CSV format:";
			`I ("Syntax:", "<$(i,ID)>,<Full name>,<$(i,Elo-rating)>");
			`P "Where $(i,ID) can be any unique string and $(i,Elo-rating) is
			    the starting rating for the player as an integer.";
			`I ("Example:", "magnus,Magnus Carlsen,2870");
			`P ""; `Noblank;
			`P "The $(i,GAMES) file should be in CSV format:";
			`I ("Syntax:", "<White's $(i,ID)>,<Black's $(i,ID)>,<$(i,RES)>");
			`P "Where the $(i,ID)s match those listed in the $(i,PLAYERS)
			    file and $(i,RES) is either $(i,1.), $(i,.5) or $(i,0.) in the
			    case of a win, draw or loss for white respectively.";
			`I ("Example:", "magnus,anand,.5");
		`S "BUGS";
			`I ("Please report bugs by opening an issue on the Elo-ladder
			     project page on Github:",
			    "https://github.com/robhoes/elo-ladder");
		]
	in
	Term.(pure print_summary $ title $ players_path $ games_path $ gh_pages),
	Term.info "ladder" ~version:"0.1a" ~doc ~man

let _ =
	match Term.eval cmd with `Error _ -> exit 1 | _ -> exit 0