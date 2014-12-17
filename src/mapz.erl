-module(mapz).

% API
-export([deep_find/2]).
-export([deep_get/2]).
-export([deep_get/3]).
-export([deep_put/3]).
-export([deep_remove/2]).
-export([deep_merge/1]).
-export([deep_merge/2]).
-export([deep_merge/3]).

%--- API ----------------------------------------------------------------------

deep_find(Path, Struct) ->
    search(Struct, Path, fun(Value) -> {ok, Value} end, fun() -> error end).

deep_get(Path, Struct) ->
    search(Struct, Path, fun(Value) -> Value end, fun() -> error(bad_key) end).

deep_get(Path, Struct, Default) ->
    search(Struct, Path, fun(Value) -> Value end, fun() -> Default end).

deep_put(Path, Value, Struct) -> recursive(Struct, Path, {set, Value}).

deep_remove(Path, Struct) -> recursive(Struct, Path, delete).

deep_merge([Map|Maps]) ->
    % Key collisions prefer maps over normal values. If a map is to be written
    % to a key, a existing normal value is overwritten and an existing  map is
    % merged.
    deep_merge(fun(#{} = V, _) -> V; (_, V) -> V end, Map, Maps).

deep_merge(First, Second) when is_map(First), is_map(Second) ->
    deep_merge([First, Second]);
deep_merge(First, Maps) when is_map(First), is_list(Maps) ->
    deep_merge([First|Maps]);
deep_merge(Fun, [Map|Maps]) when is_function(Fun, 2), is_list(Maps) ->
    deep_merge(Fun, Map, Maps).

deep_merge(_Fun, Target, []) ->
    Target;
deep_merge(Fun, Target, [From|Maps]) ->
    deep_merge(Fun, deep_merge(Fun, Target, From), Maps);
deep_merge(Fun, Target, Map) when is_map(Map) ->
    maps:fold(
        fun(K, V, T) ->
            case maps:find(K, T) of
                {ok, Value} when is_map(Value), is_map(V) ->
                    maps:put(K, deep_merge(Fun, Value, [V]), T);
                {ok, Value} ->
                    maps:put(K, Fun(Value, V), T);
                error ->
                    maps:put(K, V, T)
            end
        end,
        Target,
        Map
    ).

%--- Internal Functions -------------------------------------------------------

search(Struct, [], Wrap, _Default) ->
    Wrap(Struct);
search(Struct, [Key|Path], Wrap, Default) when is_map(Struct) ->
    case maps:find(Key, Struct) of
        {ok, Value} -> search(Value, Path, Wrap, Default);
        error       -> Default()
    end;
search(_Struct, _Path, _Wrap, Default) ->
    Default().

recursive(Struct, Path, Act) ->
    try
        rec(Struct, Path, Act)
    catch throw:not_found ->
        error(bad_key)
    end.

rec(Struct, [Key], Act) when is_map(Struct) ->
    case maps:is_key(Key, Struct) of
        true ->
            case Act of
                delete -> maps:remove(Key, Struct);
                {set, Value} -> maps:update(Key, Value, Struct)
            end;
        false ->
            case Act of
                delete -> throw(not_found);
                {set, Value} -> maps:put(Key, Value, Struct)
            end
    end;
rec(Struct, [Key|Path], Act) when is_map(Struct) ->
    case maps:find(Key, Struct) of
        {ok, Value} when is_map(Value) ->
            maps:update(Key, rec(Value, Path, Act), Struct);
        error ->
            case Act of
                delete -> throw(not_found);
                {set, _Value} -> maps:put(Key, rec(#{}, Path, Act), Struct)
            end
    end;
rec(_Struct, [], {set, Value}) when is_map(_Struct) ->
    Value.