-module(egpx).

%% egpx: egpx library's entry point.

-export([read_file/1, event_func/3, find_closest_trackpoint_time/2]).

%% Export for accessor functions.
-export([get_time/1]).

-record(gpx, {metadata, trks}).

-record(trk, {name, trksegs}).

-record(trkseg, {trkpts}).

-record(trkpt, {lat, lon, elev, time}).

%-record(state, {gpx, nest}).
-record(state, {trksegs, trkpts, curr_trkpt, nest}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Type specifications.

-opaque trkpt() :: #trkpt{}.
-export_type([trkpt/0]).

%% Define a type that is similar to datetime(), but allows fractional seconds.
-type datetime_frac() :: {{integer(),integer(),integer()}, 
                          {integer(),integer(),number()}}.

%% Define a type that is similar to datetime(), but contains a ms field for 
%% greater precision.
-type datetime_ms() ::  {{integer(),integer(),integer()}, 
                         {integer(),integer(),integer(), integer()}}.

%% API

%% @doc Use the built in SAX parser to scan the GPX file.
read_file(GpxFile) ->
    %InitState = #state{gpx = #gpx{}, nest = []},
    InitState = #state{trksegs = [], trkpts = [], curr_trkpt = #trkpt{}, nest = []},
    Options = [{event_fun, fun event_func/3}, {event_state, InitState}],
    case xmerl_sax_parser:file(GpxFile, Options) of 
        {ok, #state{trkpts = TrkPts}, _RestBin} ->
            {ok, lists:reverse(TrkPts)};
        Error -> 
            {error, Error}
    end.

%% @doc Callback to use as an EventFun.
event_func(Event, Location, State) ->
    %io:format("Ev: ~p Loc: ~p St: ~p~n", [Event, Location, State]),
    handle_event(Event, Location, State).

%% @doc Handle the events generated by the XML parser. The nest parameter is 
%% a list which gets longer with each level of nesting, allowing the 
%% hierarchy to be pattern matched.
handle_event({characters, Str}, _, #state{nest = [ele,trkpt,trkseg,trk,gpx]} = State) ->
    {Elevation, []} = string:to_float(Str),
    %io:format("Elevation ~p~n", [Elevation]),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{elev = Elevation},
    State#state{curr_trkpt = NewPt};

handle_event({characters, Str}, _, #state{nest = [time,trkpt,trkseg,trk,gpx]} = State) ->
    %io:format("Time string ~p~n", [Str]),
    DateTime = string_to_datetime_frac(Str),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{time = DateTime},
    State#state{curr_trkpt = NewPt};

handle_event({startElement, _, "trkpt" = LocalName, _, Attr},
             _, 
             #state{nest = [trkseg,trk,gpx], curr_trkpt = TrkPt} = State) ->
    {Lat, Lon} = attributes_to_lat_lon(Attr), 
    NewPt = TrkPt#trkpt{lat = Lat, lon = Lon},
    NewState = State#state{curr_trkpt = NewPt},
    %io:format("Lat ~p, Lon ~p~n", [Lat, Lon]),
    add_nest(NewState, LocalName);

handle_event({startElement, _, LocalName, _, _}, _, State) ->
    add_nest(State, LocalName);

handle_event({endElement, _, "trkpt", _}, _, State) ->
    #state{trkpts = TkPts, curr_trkpt = TrkPt} = State,
    %io:format("Finishing trackpoint~n"),
    NewTkPts = [TrkPt|TkPts],
    NewState = State#state{trkpts = NewTkPts, curr_trkpt = #trkpt{}},
    reduce_nest(NewState, "trkpt");

handle_event({endElement, _, LocalName, _}, _, State) ->
    reduce_nest(State, LocalName);

handle_event(_, _, State) -> State.

%% @doc Deepen the nesting level in the state variable.
add_nest(State, LocalName) ->
    #state{nest = Nest} = State,
    NewNest = [tag_to_atom(LocalName)|Nest],
    State#state{nest = NewNest}.

%% @doc Reduce the nesting by one level. Check for matching name pairs (where
%% we recognised the tag, others are all mapped to undefined).
reduce_nest(#state{nest = Nest} = State, LocalName) ->
    Tag = tag_to_atom(LocalName),
    [Tag|NewNest] = Nest,
    State#state{nest = NewNest}.


%% @doc Find the trackpoint that is closest to the specified time.
-spec find_closest_trackpoint_time(
        [trkpt()], datetime_ms()) -> {error} | {ok, trkpt()}.

find_closest_trackpoint_time([], _) ->
    {error};
find_closest_trackpoint_time(
    [FirstTP|RemTP] = Trackpoints, 
    {{_Year,_Month,_Day},{_Hour,_Min,_Sec,_Ms}} = DateTimeMS) 
    when is_list(Trackpoints) ->
        find_time(FirstTP, RemTP, DateTimeMS).

%% @doc Helper function to scan a list of trackpoints for the closest match.
-spec find_time(trkpt(), [trkpt()], datetime_ms()) -> trkpt().

find_time(PrevTP, [], _DateTimeMS) ->
    {ok, PrevTP};
find_time(PrevTP, [NextTP|Rem], DateTimeMS) ->
    PrevMS = datetime_frac_to_gregorian_ms(get_time(PrevTP)),
    NextMS = datetime_frac_to_gregorian_ms(get_time(NextTP)),
    SearchMS = datetime_ms_to_gregorian_ms(DateTimeMS),
    case PrevMS >= SearchMS of
        true ->
            {ok, PrevTP};
        false ->
            case NextMS >= SearchMS of
                true ->
                    % Point of interest lies in the interval.
                    {ok, get_closest(PrevTP, NextTP, DateTimeMS)};
                false ->
                    % Haven't reached the point yet, recurse. 
                    find_time(NextTP, Rem, DateTimeMS)
            end
    end.  

%% @doc Select which of the two trackpoints are closest to the specified time.
-spec get_closest(trkpt(), trkpt(), datetime_ms()) -> trkpt().

get_closest(TP1, TP2, DateTimeMS) ->
    RefGregMS = datetime_ms_to_gregorian_ms(DateTimeMS),
    DateTime1 = get_time(TP1),
    DateTime2 = get_time(TP2),
    GregMS1 = datetime_frac_to_gregorian_ms(DateTime1),
    GregMS2 = datetime_frac_to_gregorian_ms(DateTime2),
    Delta1 = GregMS1 - RefGregMS,
    Delta2 = GregMS2 - RefGregMS,
    case abs(Delta1) =< abs(Delta2) of
        true  -> TP1;
        false -> TP2
    end.

%% @doc Convert a datetime_frac() to a datetime_ms().
-spec datetime_frac_to_datetime_ms(datetime_frac()) -> datetime_ms(). 

datetime_frac_to_datetime_ms({Date,{H,M,FS}}) ->
    Sec = trunc(FS),
    Rem = FS - Sec,
    MS = round(Rem * 1000),
    {Date,{H,M,Sec,MS}}.

%% @doc Convert datetime_ms() to datetime(). Drops the MS field.
-spec datetime_ms_to_datetime(datetime_ms()) -> calendar:datetime().
datetime_ms_to_datetime({Date, {H,M,S,_MS}}) ->
    {Date,{H,M,S}}.

%% Convert datetime() to Gregorian MS.
datetime_frac_to_gregorian_ms(DateTimeFrac) ->
    DateTimeMS = datetime_frac_to_datetime_ms(DateTimeFrac),
    datetime_ms_to_gregorian_ms(DateTimeMS).

%% Convert datetime_ms() to Gregorian MS.
datetime_ms_to_gregorian_ms({_Date,{_,_,_,MS}} = DateTimeMS) ->
    DateTime = datetime_ms_to_datetime(DateTimeMS),
    GregSec = calendar:datetime_to_gregorian_seconds(DateTime),
    GregMS = 1000 * GregSec + MS,
    GregMS.

%% @doc Map tags to atoms.
-spec tag_to_atom(string()) -> atom().
tag_to_atom("gpx")        -> gpx;
tag_to_atom("trk")        -> trk;
tag_to_atom("name")       -> name;
tag_to_atom("trkseg")     -> trkseg;
tag_to_atom("trkpt")      -> trkpt;
tag_to_atom("ele")        -> ele;
tag_to_atom("time")       -> time;
tag_to_atom(_)            -> undefined.

%% @doc Extract the Lat, Lon from attributes. Assumes fixed ordering at present.
attributes_to_lat_lon([{_,_,"lat",LatStr},{_,_,"lon",LonStr}|_]) ->
    {NumLat, []} = string:to_float(LatStr),
    {NumLon, []} = string:to_float(LonStr),
    {NumLat, NumLon}.

%% @doc Convert the date/time string of the form "2009-10-17T18:37:31Z" to a
%% datetime_frac().
string_to_datetime_frac(DateTimeStr) when is_list(DateTimeStr) ->
    [DateStr, TimeStr] = string:tokens(DateTimeStr, "T"),
    [YearStr, MonthStr, DayStr] = string:tokens(DateStr, "-"),
    {Year, []} = string:to_integer(YearStr),
    {Month, []} = string:to_integer(MonthStr),
    {Day, []} = string:to_integer(DayStr),
    [HourStr, MinStr, SecStr] = string:tokens(TimeStr, ":"),
    {Hour, []} = string:to_integer(HourStr),
    {Min, []} = string:to_integer(MinStr),
    Sec = string_to_number(SecStr),   % Discards trailing Z.
    {{Year,Month,Day},{Hour,Min,Sec}}.

%% @doc Convert a string which may begin with an integer or float to a number.
string_to_number(NumStr) ->
    case string:to_float(NumStr) of
        {error, no_float} -> 
            {X, _} = string:to_integer(NumStr), 
            X;
        {X, _}            -> 
            X
    end.

%% @doc Accessor functions.

get_time(#trkpt{time = X}) -> X.
