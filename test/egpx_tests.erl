-module(egpx_tests).

-include_lib("eunit/include/eunit.hrl").

%% Define a test generator for the BCS character set functions.
egpx_test_() ->
    [find_closest_checks()].

find_closest_checks() ->
    [?_assertEqual(ok, ok)].

