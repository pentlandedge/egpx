-module(egpx).

%% egpx: egpx library's entry point.

-export([read_file/2]).


%% API

read_file(GpxFile, XsdSchema) ->
    {ok, Model} = erlsom:compile_xsd_file(XsdSchema), 
    {ok, Xml} = file:read_file(GpxFile),
    {ok, Result, _} = erlsom:scan(Xml, Model),
    {ok, Result}.


%% End of Module.
