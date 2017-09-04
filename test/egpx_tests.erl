-module(egpx_tests).

-include_lib("eunit/include/eunit.hrl").

%% Define a test generator for the BCS character set functions.
egpx_test_() ->
    [find_closest_checks()].

find_closest_checks() ->
    {ok, Gpx} = egpx:read_file("../test/wiki.gpx"),
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
     ?_assertEqual({{2009,10,17},{18,37,34}}, Time3)
    ].

