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
%% @doc Test routines for the egpx module. 

-module(egpx_tests).

-include_lib("eunit/include/eunit.hrl").

%% Define a test generator for the BCS character set functions.
egpx_test_() ->
    [find_closest_checks(), garmin_checks(), garmin_run_checks()].

find_closest_checks() ->
    {ok, Gpx} = egpx:read_file("../test/wiki.gpx"),
    [Trk1|_] = egpx:get_tracks(Gpx),
    Trk1Name = egpx:get_track_name(Trk1),
    Trackpoints = egpx:merge_trackpoints(Gpx),
    % Check an empty list of trackpoints produces an error.
    {error} = egpx:find_closest_trackpoint_time([], {{2009,10,17},{18,37,25,500}}),
    % Seach before start of trackpoint list.
    {ok, TP1} = egpx:find_closest_trackpoint_time(Trackpoints, {{2009,10,17},{18,37,25,500}}),
    Time1 = egpx:get_time(TP1),    
    % Seach in between two points. 
    {ok, TP2} = egpx:find_closest_trackpoint_time(Trackpoints, {{2009,10,17},{18,37,30,0}}),
    Time2 = egpx:get_time(TP2),    
    % Search date beyond end of list but time before first point.
    {ok, TP3} = egpx:find_closest_trackpoint_time(Trackpoints, {{2009,10,18},{18,37,25,500}}),
    Time3 = egpx:get_time(TP3),    
    [?_assertEqual({{2009,10,17},{18,37,26}}, Time1),
     ?_assertEqual({{2009,10,17},{18,37,31}}, Time2),
     ?_assertEqual({{2009,10,17},{18,37,34}}, Time3),
     ?_assertEqual("Example GPX Document", Trk1Name)
    ].

garmin_checks() ->
    {Ret, _Gpx} = egpx:read_file("../test/garmin_sample.gpx"),
    [?_assertEqual(ok, Ret)].

garmin_run_checks() ->
    {Ret, _Gpx} = egpx:read_file("../test/garmin_run.gpx"),
    [?_assertEqual(ok, Ret)].
