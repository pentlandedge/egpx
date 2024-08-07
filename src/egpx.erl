%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright 2017 Pentland Edge Ltd.
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. 
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software 
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT 
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the 
%% License for the specific language governing permissions and limitations 
%% under the License.
%% 
%% @doc Utilities for manipulating GPX encoded GPS data.

-module(egpx).

%% egpx: egpx library's entry point.

-export([
    read_file/1, 
    read_bin/1, 
    event_func/3, 
    find_closest_trackpoint_time/2, 
    merge_trackpoints/1,
    trackpoints_to_csv_iolist/1]).

%% Export for accessor functions.
-export([
    get_tracks/1, 
    get_track_name/1,
    get_segs/1,
    get_trackpoints/1, 
    get_lat/1,
    get_lon/1,
    get_elev/1,
    get_time/1,
    get_hdop/1,
    get_speed/1,
    get_hr/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Record definitions for building a structured representation of the 
%% GPX file.

-record(gpx, {metadata, trks}).

-record(trk, {name, trksegs}).

-record(trkseg, {trkpts}).

-record(trkpt, {lat, lon, elev, time, hdop, speed, hr}).

-record(state, {gpx, curr_trk, trkpts, curr_trkpt, nest}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Type specifications.

-opaque gpx() :: #gpx{}.
-export_type([gpx/0]).

-opaque trk() :: #trk{}.
-export_type([trk/0]).

-opaque trkseg() :: #trkseg{}.
-export_type([trkseg/0]).

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
    InitState = #state{
        gpx = #gpx{trks = []},
        curr_trk = #trk{trksegs = []},
        trkpts = [], 
        curr_trkpt = #trkpt{}, 
        nest = []},

    Options = [{event_fun, fun event_func/3}, {event_state, InitState}],
    case xmerl_sax_parser:file(GpxFile, Options) of 
        {ok, #state{gpx = Gpx}, _RestBin} ->
            {ok, Gpx};
        Error -> 
            {error, Error}
    end.

%% @doc Use the built in SAX parser to scan the UTF8 encoded binary.
read_bin(GpxBin) ->
    InitState = #state{
        gpx = #gpx{trks = []},
        curr_trk = #trk{trksegs = []},
        trkpts = [], 
        curr_trkpt = #trkpt{}, 
        nest = []},

    Options = [{event_fun, fun event_func/3}, {event_state, InitState}],
    case xmerl_sax_parser:stream(GpxBin, Options) of 
        {ok, #state{gpx = Gpx}, _RestBin} ->
            {ok, Gpx};
        Error -> 
            {error, Error}
    end.

%% @doc Callback to use as an EventFun.
event_func(Event, Location, State) ->
    %io:format("Event: ~p, Loc ~p, State: ~p~n", [Event, Location, State]),
    handle_event(Event, Location, State).

%% @doc Handle the events generated by the XML parser. The nest parameter is 
%% a list which gets longer with each level of nesting, allowing the 
%% hierarchy to be pattern matched.
handle_event({characters, Str}, _, #state{nest = [name,trk,gpx]} = State) ->
    Trk = State#state.curr_trk,
    NewTrk = Trk#trk{name = Str},
    State#state{curr_trk = NewTrk};

handle_event({characters, Str}, _, #state{nest = [ele,trkpt,trkseg,trk,gpx]} = State) ->
    Elevation = string_to_number(Str),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{elev = Elevation},
    State#state{curr_trkpt = NewPt};

handle_event({characters, Str}, _, #state{nest = [time,trkpt,trkseg,trk,gpx]} = State) ->
    DateTime = string_to_datetime_frac(Str),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{time = DateTime},
    State#state{curr_trkpt = NewPt};

handle_event({characters, Str}, _, #state{nest = [hdop,trkpt,trkseg,trk,gpx]} = State) ->
    Hdop = string_to_number(Str),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{hdop = Hdop},
    State#state{curr_trkpt = NewPt};

% Bad Elf speed extension to trackpoints.
handle_event({characters, Str}, _, #state{nest = [speed,extensions,trkpt,trkseg,trk,gpx]} = State) ->
    Speed = string_to_number(Str),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{speed = Speed},
    State#state{curr_trkpt = NewPt};

% Garmin TrackPointExtension containing a nested heart rate element.
handle_event({characters, Str}, _, #state{nest = [hr,track_point_ext,extensions,trkpt,trkseg,trk,gpx]} = State) ->
    HeartRate = string_to_number(Str),
    TrkPt = State#state.curr_trkpt,
    NewPt = TrkPt#trkpt{hr = HeartRate},
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
    #state{trkpts = TrkPts, curr_trkpt = TrkPt} = State,
    %io:format("Finishing trackpoint~n"),
    NewTrkPts = [TrkPt|TrkPts],
    NewState = State#state{trkpts = NewTrkPts, curr_trkpt = #trkpt{}},
    reduce_nest(NewState, "trkpt");

handle_event({endElement, _, "trkseg", _}, _, State) ->
    #state{curr_trk = Trk, trkpts = TrkPts} = State,
    NewSeg = #trkseg{trkpts = lists:reverse(TrkPts)},
    NewTrkPts = [],
    TrkSegs = Trk#trk.trksegs,
    NewTrk = Trk#trk{trksegs = [NewSeg|TrkSegs]},
    NewState = State#state{curr_trk = NewTrk, trkpts = NewTrkPts},
    reduce_nest(NewState, "trkseg");

handle_event({endElement, _, "trk", _}, _, State) ->
    #state{gpx = Gpx, curr_trk = Trk} = State,
    Trks = Gpx#gpx.trks,
    NewGpx = Gpx#gpx{trks = [Trk|Trks]}, 
    NewState = State#state{gpx = NewGpx, curr_trk = #trk{}},
    reduce_nest(NewState, "trk");

handle_event({endElement, _, "gpx", _}, _, State) ->
    #state{gpx = Gpx} = State,
    Trks = Gpx#gpx.trks,
    NewGpx = Gpx#gpx{trks = lists:reverse(Trks)}, 
    NewState = State#state{gpx = NewGpx},
    reduce_nest(NewState, "gpx");

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
-spec find_time(trkpt(), [trkpt()], datetime_ms()) -> {ok, trkpt()}.

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
-spec tag_to_atom(string())         -> atom().
tag_to_atom("gpx")                  -> gpx;
tag_to_atom("trk")                  -> trk;
tag_to_atom("name")                 -> name;
tag_to_atom("trkseg")               -> trkseg;
tag_to_atom("trkpt")                -> trkpt;
tag_to_atom("ele")                  -> ele;
tag_to_atom("time")                 -> time;
tag_to_atom("hdop")                 -> hdop;
tag_to_atom("extensions")           -> extensions;
tag_to_atom("speed")                -> speed;
tag_to_atom("TrackPointExtension")  -> track_point_ext;
tag_to_atom("hr")                   -> hr;
tag_to_atom(_)                      -> undefined.

%% @doc Extract the Lat, Lon from attributes. 
attributes_to_lat_lon([{_,_,"lat",LatStr},{_,_,"lon",LonStr}|_]) ->
    lat_lon_strings_to_tuple(LatStr, LonStr);
attributes_to_lat_lon([{_,_,"lon",LonStr},{_,_,"lat",LatStr}|_]) ->
    lat_lon_strings_to_tuple(LatStr, LonStr).

%% @doc Helper function to convert Lat, Lon strings to a tuple containing 
%% the numerical values.
lat_lon_strings_to_tuple(LatStr, LonStr) ->
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

%% @doc Merge trackpoints from all segments into a single list.
merge_trackpoints(#gpx{trks = Trks}) -> 
    % Decompose into individual tracks and merge the trackpoints for each
    % list of segments. Flatten the result.
    F = fun(Trk) ->
            Segs = get_segs(Trk),
            merge_trackpoints(Segs)
        end,
    NestedList = lists:map(F, Trks),
    lists:flatten(NestedList);
    
merge_trackpoints(SegList) when is_list(SegList) ->
    NestedList = lists:map(fun get_trackpoints/1, SegList),
    lists:flatten(NestedList).

%% @doc Write a flat list of trackpoints to an iolist in CSV format.
trackpoints_to_csv_iolist(Trackpoints) ->
    % Define a local function to increment a record number as the accumulator
    % in a mapfold.
    F = fun(Trackpoint, RecNum) ->
            IoList = trackpoint_to_csv_iolist(RecNum, Trackpoint), 
            {IoList, RecNum+1}
        end,
    {IoList, _} = lists:mapfoldl(F, 1, Trackpoints),
    ColHdr = col_hdr_iolist(),
    [ColHdr|IoList].

%% @doc Convert a single trackpoint to a CSV formatted iolist().
%% Need to add header row in the form:
%% Record Number,Date,Time,Latitude,Longitude,Speed(km/h),Altitude(meters)
trackpoint_to_csv_iolist(RecNum, Trackpoint) ->
    RecNumStr = io_lib:format("~p,", [RecNum]),
    {Date,TimeFrac} = get_time(Trackpoint),
    DateIO = date_to_iolist(Date),
    TimeIO = time_to_iolist(TimeFrac),
    SpeedIO = speed_to_iolist(get_speed(Trackpoint)),
    Args = [get_lat(Trackpoint),
            get_lon(Trackpoint),
            get_elev(Trackpoint)],
    ArgsIO = io_lib:format(",~p,~p,~p,", Args),
    NL = io_lib:format("~n", []),
    [RecNumStr, DateIO, ",", TimeIO, ArgsIO, SpeedIO, NL].

%% @doc Return a column of header strings as an iolist().
col_hdr_iolist() ->
    Hdr = "Record Number,Date,Time,Latitude,Longitude,Altitude(m msl),"
          "Speed(m/s)~n",
    io_lib:format(Hdr, []).

%% @doc Convert a date tuple into a display string.
date_to_iolist({Yr,Mon,Day}) ->
    io_lib:format("~p-~p-~p", [Yr, Mon, Day]).

%% @doc Convert a time to a string.
time_to_iolist({Hr,Min,Sec}) when is_float(Sec) ->
    io_lib:format("~2..0w:~2..0w:~6.3.0f", [Hr, Min, Sec]);
time_to_iolist({Hr,Min,Sec}) ->
    io_lib:format("~2..0w:~2..0w:~2..0w", [Hr, Min, Sec]).

%% @doc Convert a speed to a string. If undefined, map to empty.
speed_to_iolist(undefined) -> [];
speed_to_iolist(Speed)     -> io_lib:format("~p", [Speed]).

%% @doc Accessor functions.
get_tracks(#gpx{trks = X}) -> X.
get_track_name(#trk{name = X}) -> X.
get_segs(#trk{trksegs = X}) -> X.
get_trackpoints(#trkseg{trkpts = X}) -> X.
get_lat(#trkpt{lat = X}) -> X.
get_lon(#trkpt{lon = X}) -> X.
get_elev(#trkpt{elev = X}) -> X.
get_time(#trkpt{time = X}) -> X.
get_hdop(#trkpt{hdop = X}) -> X.
get_speed(#trkpt{speed = X}) -> X.
get_hr(#trkpt{hr = X}) -> X.

