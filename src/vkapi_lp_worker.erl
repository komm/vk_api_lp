-module(vkapi_lp_worker).
-define(VER, "v=5.45").
-define(URL, "https://api.vk.com/method/").
-define(TIMEOUT, 30).
-export([start/1]).

start(Token) when is_binary(Token)->
    start(binary_to_list(Token))
;
start(Token) when is_list(Token)->
    inets:start(),
    ssl:start(),
    application:start(jsx),
    case httpc:request(get, {?URL "messages.getLongPollServer?" ?VER "&access_token=" ++ Token, []}, [], [{body_format, binary}]) of
    {ok, {{"HTTP/1.1",200,"OK"}, _Header, Body}}->
        {<<"response">>, Resp} = lists:keyfind(<<"response">>, 1, jsx:decode(Body)),
        {{_, Key1}, {_, Srv1}, {_, Ts1}} = { lists:keyfind(<<"key">>, 1, Resp),
                                             lists:keyfind(<<"server">>, 1, Resp), 
                                             lists:keyfind(<<"ts">>, 1, Resp)}
    end,
    case connectLongPolling(Srv1, Key1, Ts1) of
    renew->
        start(Token)
    ;
    Strange->
        error_logger:info_report([{?MODULE, ?FUNCTION_NAME}, {strange, Strange}]),
        {exit, strange}
    end
.


connectLongPolling(Server, Key, Ts)->
    case httpc:request(get, {"https://"++ binary_to_list(Server) ++
                            "?act=a_check&key=" ++ binary_to_list(Key) ++ 
                            "&ts=" ++ integer_to_list(Ts) ++ 
                            "&wait=" ++ integer_to_list(?TIMEOUT) ++
                            "&mode=2", 
                  []}, [], [{body_format, binary}]) of
    {ok, {{"HTTP/1.1",200,"OK"}, _Header, Body}}->
        Parsed = jsx:decode(Body),
        case lists:keyfind(<<"failed">>, 1, Parsed) of
        {<<"failed">>, 1}->
            {<<"ts">>, NewTs} = lists:keyfind(<<"ts">>, 1, Parsed),
	    connectLongPolling(Server, Key, NewTs)
        ;
        {<<"failed">>, 2}->
            renew
        ;
        {<<"failed">>, 3}->
            renew
        ;
        {<<"failed">>, 4}->
            error_logger:error_report([{?MODULE, ?FUNCTION_NAME}, {failed, 4, bad_version}]),
            {error, bad_version}
        ;
        false->   
            {<<"ts">>, NewTs} = lists:keyfind(<<"ts">>, 1, Parsed),
            {<<"updates">>, Upd} = lists:keyfind(<<"updates">>, 1, Parsed),
            parsed(Upd),
            error_logger:info_report([{?MODULE, ?FUNCTION_NAME}, {new_connect, update_ts, NewTs}]),
            connectLongPolling(Server, Key, NewTs)
        end
    ;
    {ok, {{"HTTP/1.1",504,"Gateway Time-out"}, _Header, _Body}}->
        error_logger:info_report([{?MODULE, ?FUNCTION_NAME, timeout}]),
        connectLongPolling(Server, Key, Ts)
    ;
    Error->
        error_logger:info_report([{?MODULE, ?FUNCTION_NAME, {error, Error}}])
    end
.

parsed([H|_] = List) when is_list(H)->
    [parsed(X) || X <- List]
;
parsed([1, _MessageId, _Flags])->ok;
parsed([2, _MessageId, _Mask, _UserIds])->ok;
parsed([3, _MessageId, _Mask, _PeerIds])->ok;
parsed([4, MessageId, Flag, FromId, Timestamp, Subject, Text, Attachments])->
    error_logger:info_report([{new_message, MessageId, Flag, FromId, Timestamp, Subject, Text, Attachments}]),
    {ok, {new_message, MessageId, Flag, FromId, Timestamp, Subject, Text, Attachments}}
;
parsed([6, _PeerId, _LocalId])->ok;
parsed([7, _PeerId, _LocalId])->ok;
parsed([8, _UserId, _Extra])->ok; %% UserId is (-+)
parsed([9, _UserId, _Flags])->ok; %% Flags is 0 | 1 is exit | timeout
parsed([10, _PeerId, _Mask])->ok;
parsed([11, _PeerId, _Flags])->ok;
parsed([12, _PeerId, _Mask])->ok;
parsed([51, _ChatId, _Self])->ok;
parsed([61, _UserId, _Flags])->ok;
parsed([62, _UserId, _ChatId])->ok;
parsed([70, _UserId, _CallId])->ok;
parsed([80, _Count, 0])->ok;
parsed([114, _PeerId, _Sound, _DisabledUntil ])->ok;
parsed(Strange)->
    error_logger:info_report([{?MODULE, ?FUNCTION_NAME}, {strange, Strange}]),
    ok
.

