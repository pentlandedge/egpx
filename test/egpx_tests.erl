-module(egpx_tests).

-include_lib("eunit/include/eunit.hrl").

%% Define a test generator for the BCS character set functions.
egpx_test_() ->
    [find_closest_checks()].

find_closest_checks() ->
    {ok, Trackpoints} = egpx:read_file("../test/wiki.gpx"),
    {ok, TP1} = egpx:find_closest_trackpoint_time(Trackpoints, {{2009,10,17},{18,37,25,500}}),
    Time1 = egpx:get_time(TP1),    
    [?_assertEqual({{2009,10,17},{18,37,26}}, Time1)].

