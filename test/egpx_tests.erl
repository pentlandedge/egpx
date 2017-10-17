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
    {Ret, Gpx} = egpx:read_file("../test/garmin_sample.gpx"),
    [Trk1] = egpx:get_tracks(Gpx),
    Trk1Name = egpx:get_track_name(Trk1),
    [Seg] = egpx:get_segs(Trk1),
    Trackpoints = egpx:get_trackpoints(Seg),
    [Pt1|_] = Trackpoints,
    [?_assertEqual(ok, Ret),
     ?_assertEqual("Run at  river side", Trk1Name),
     ?_assert(almost_equal(25.06334876641631, egpx:get_lat(Pt1), 0.000001)),
     ?_assert(almost_equal(121.6330941952765, egpx:get_lon(Pt1), 0.000001)),
     ?_assert(almost_equal(19.799999237060547, egpx:get_elev(Pt1), 0.000001))
     | time_checks({{2015,1,20},{13,26,30.0}}, egpx:get_time(Pt1))].

garmin_run_checks() ->
    {Ret, _Gpx} = egpx:read_file("../test/garmin_run.gpx"),
    [?_assertEqual(ok, Ret)].

%% Utility function to generate time checks
time_checks({{Y1,M1,D1},{H1,Min1,S1}}, {{Y2,M2,D2},{H2,Min2,S2}}) ->
    [?_assertEqual(Y1, Y2),
     ?_assertEqual(M1, M2),
     ?_assertEqual(D1, D2),
     ?_assertEqual(H1, H2),
     ?_assertEqual(Min1, Min2),
     ?_assert(almost_equal(S1, S2, 0.000001))].

%% Utility function to compare whether floating point values are within a 
%% specified range.
almost_equal(V1, V2, Delta) ->
    abs(V1 - V2) =< Delta.

