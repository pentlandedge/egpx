# egpx
GPX (GPS Exchange Format) utilities written in Erlang. It is currently under development. 

It's primary purpose is to support tracking applications, and it should be capable of safe operation on a server. Initial work is focused on extracting common standard fields and ignoring everything else. Vendor extensions will be handled in the library rather than fetching untrusted schema from the web. Schema loading may be added at a later date.

From initial testing, it appears to cope with most standard elements, but many vendor extensions are ignored.

## Building
It is necessary to have Erlang installed, and the compiler erlc available on the path. The rebar tool is used to control the build process, so it is also necessary to have a copy of rebar available on the path. The software can be built (on a Linux platform) using rebar:
```
# rebar compile
```
## Interactive decoding of a GPX file
From the root directory, the Erlang shell can be started as follows:
```
# rebar shell
```
From the Erlang prompt, a GPX encoded file can be read in the following manner: 
```
1> {ok, Gpx} = egpx:read_file("/path/to/file.gpx").
```
The variable Gpx will then contain a representation of the file in structured form which can be used for further processing.

## Extracting a flat list of trackpoints
The Gpx structure (see above) can be converted to a flat list of trackpoints:
```
2> TrackPoints = egpx:merge_trackpoints(Gpx).
```
All track segments will be combined into a single list.

## Extracting trackpoint data.
Accessor functions have been provided to allow access to trackpoint elements. For example, to extract the Latitude and Longitude of the first trackpoint:
```
3> [TP|_] = TrackPoints.
4> Lat = egpx:get_lat(TP).
5> Lon = egpx:get_lon(TP).
```
These can of course be combined into an Erlang fun and used with the standard higher order functions for list processing such as map and fold.

## Searching for the closest matching time.
It is often useful to search the list of trackpoints for the closest matching time (specified as UTC). This is currently a simple linear search. This takes a list of trackpoints and a date/time similar to a standard datetime() element, but has an added element to permit millisecond precision {{Year,Month,Day},{Hour,Min,Sec,MilliSecs}}. For example, to search for the closest match in time to 20:56:23.153 on 1st October 2017:
```
6> TP2 = egpx:find_closest_trackpoint_time(TrackPoints, {{2017,10,1},{20,56,23,153}}.
```
The efficency of this search will be improved soon.

