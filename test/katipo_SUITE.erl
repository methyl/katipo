-module(katipo_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-define(POOL, katipo_test_pool).
-define(POOL_SIZE, 2).

suite() ->
    [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
    application:ensure_all_started(katipo),
    application:ensure_all_started(meck),
    {ok, _} = katipo_pool:start(?POOL, ?POOL_SIZE),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(katipo).

init_per_group(session, Config) ->
    application:ensure_all_started(katipo),
    Config;
init_per_group(pool, Config) ->
    application:ensure_all_started(meck),
    Config;
init_per_group(https, Config) ->
    application:ensure_all_started(cowboy),
    Dispatch = cowboy_router:compile([{'_', [{"/", get_handler, []}]}]),
    DataDir = ?config(data_dir, Config),
    CACert = filename:join(DataDir, "cowboy-ca.crt"),
    {ok, _} = cowboy:start_https(ct_https, 1,
                                 [{port, 8443},
                                  {cacertfile, CACert},
                                  {certfile, filename:join(DataDir, "server.crt")},
                                  {keyfile, filename:join(DataDir, "server.key")}],
                                 [{env, [{dispatch, Dispatch}]}]),
    [{cacert_file, list_to_binary(CACert)} | Config];
init_per_group(proxy, Config) ->
    application:ensure_all_started(http_proxy),
    Config;
init_per_group(_, Config) ->
    Config.

end_per_group(pool, Config) ->
    application:stop(meck),
    Config;
end_per_group(proxy, Config) ->
    application:stop(http_proxy),
    Config;
end_per_group(_, Config) ->
    Config.

init_per_testcase(TestCase, Config)
  when TestCase == proxy_get orelse TestCase == proxy_post_data ->
    {ok, HttpProxyService} = http_proxy:start(3128, []),
    [{http_proxy, HttpProxyService} | Config];
init_per_testcase(_, Config) ->
    Config.

end_per_testcase(TestCase, Config)
  when TestCase == proxy_get orelse TestCase == proxy_post_data ->
    HttpProxyService = ?config(http_proxy, Config),
    ok = http_proxy:stop(HttpProxyService),
    proplists:delete(http_proxy, Config);
end_per_testcase(_, Config) ->
    Config.

groups() ->
    [{http, [parallel],
      [get,
       get_req,
       head,
       post_data,
       post_iodata,
       post_arity_2,
       post_qs,
       post_req,
       url_missing,
       bad_method,
       put_data,
       put_arity_2,
       put_qs,
       patch_data,
       patch_arity_2,
       patch_qs,
       options,
       headers,
       header_remove,
       delete,
       gzip,
       deflate,
       stream,
       statuses,
       cookies,
       cookies_delete,
       cookies_bad_cookie_jar,
       bytes,
       stream_bytes,
       utf8,
       redirect_to,
       connecttimeout_ms,
       followlocation_true,
       followlocation_false,
       tcp_fastopen_true,
       tcp_fastopen_false,
       timeout_ms,
       maxredirs,
       basic_unauthorised,
       basic_authorised,
       digest_unauthorised,
       digest_authorised,
       badopts,
       proxy_couldnt_connect]},
     {pool, [],
      [pool_start_stop,
       worker_death,
       port_death,
       port_late_response,
       pool_opts]},
     {https, [],
      [verify_host_verify_peer_ok,
       verify_host_verify_peer_error,
       cacert_self_signed]},
     {proxy, [],
      [proxy_get,
       proxy_post_data]},
     {session, [parallel],
      [session_new,
       session_new_bad_opts,
       session_new_cookies,
       session_new_headers,
       session_update,
       session_update_bad_opts]},
     {port, [],
      [max_total_connections]},
     {metrics, [],
      [metrics_true,
       metrics_false]}].

all() ->
    [{group, http},
     {group, pool},
     {group, https},
     {group, proxy},
     {group, session},
     {group, port},
     {group, metrics}].

get(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:get(?POOL, <<"http://httpbin.org/get?a=%21%40%23%24%25%5E%26%2A%28%29_%2B">>),
    Json = jsx:decode(Body),
    [{<<"a">>, <<"!@#$%^&*()_+">>}] = proplists:get_value(<<"args">>, Json).

get_req(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:req(?POOL, #{url => <<"http://httpbin.org/get?a=%21%40%23%24%25%5E%26%2A%28%29_%2B">>}),
    Json = jsx:decode(Body),
    [{<<"a">>, <<"!@#$%^&*()_+">>}] = proplists:get_value(<<"args">>, Json).

head(_) ->
    {ok, #{status := 200}} =
        katipo:head(?POOL, <<"http://httpbin.org/get">>).

post_data(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:post(?POOL, <<"http://httpbin.org/post">>,
                    #{headers => [{<<"Content-Type">>, <<"application/json">>}],
                      body => <<"!@#$%^&*()">>}),
    Json = jsx:decode(Body),
    <<"!@#$%^&*()">> = proplists:get_value(<<"data">>, Json).

post_iodata(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:post(?POOL, <<"http://httpbin.org/post">>,
                    #{headers => [{<<"Content-Type">>, <<"application/json">>}],
                      body => [<<"!@#$%">>, <<"^&*()">>]}),
    Json = jsx:decode(Body),
    <<"!@#$%^&*()">> = proplists:get_value(<<"data">>, Json).

post_arity_2(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:post(?POOL, <<"http://httpbin.org/post">>),
    Json = jsx:decode(Body),
    undefined = proplists:get_value(<<>>, Json).

post_qs(_) ->
    QsVals = [{<<"foo">>, <<"bar">>}, {<<"baz">>, true}],
    {ok, #{status := 200, body := Body}} =
        katipo:post(?POOL, <<"http://httpbin.org/post">>, #{body => QsVals}),
    Json = jsx:decode(Body),
    [] = [{<<"baz">>,<<>>},{<<"foo">>,<<"bar">>}] -- proplists:get_value(<<"form">>, Json).

post_req(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:req(?POOL, #{url => <<"http://httpbin.org/post">>,
                     method => post,
                     headers => [{<<"Content-Type">>, <<"application/json">>}],
                     body => <<"!@#$%^&*()">>}),
    Json = jsx:decode(Body),
    <<"!@#$%^&*()">> = proplists:get_value(<<"data">>, Json).

url_missing(_) ->
    Message = [{url, undefined}],
    BinaryMessage = iolist_to_binary(io_lib:format("~p", [Message])),
    {error, #{code := bad_opts, message := BinaryMessage}} =
        katipo:req(?POOL, #{method => post,
                     headers => [{<<"Content-Type">>, <<"application/json">>}],
                     body => <<"!@#$%^&*()">>}).

bad_method(_) ->
    Message = [{method, toast}],
    BinaryMessage = iolist_to_binary(io_lib:format("~p", [Message])),
    {error, #{code := bad_opts, message := BinaryMessage}} =
        katipo:req(?POOL, #{method => toast,
                     headers => [{<<"Content-Type">>, <<"application/json">>}],
                     body => <<"!@#$%^&*()">>}).

put_data(_) ->
    Headers = [{<<"Content-Type">>, <<"application/json">>}],
    {ok, #{status := 200, body := Body}} =
        katipo:put(?POOL, <<"http://httpbin.org/put">>,
                   #{headers => Headers, body => <<"!@#$%^&*()">>}),
    Json = jsx:decode(Body),
    <<"!@#$%^&*()">> = proplists:get_value(<<"data">>, Json).

put_arity_2(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:put(?POOL, <<"http://httpbin.org/put">>),
    Json = jsx:decode(Body),
    undefined = proplists:get_value(<<>>, Json).

put_qs(_) ->
    QsVals = [{<<"foo">>, <<"bar">>}, {<<"baz">>, true}],
    {ok, #{status := 200, body := Body}} =
        katipo:put(?POOL, <<"http://httpbin.org/put">>, #{body => QsVals}),
    Json = jsx:decode(Body),
    [] = [{<<"baz">>,<<>>},{<<"foo">>,<<"bar">>}] -- proplists:get_value(<<"form">>, Json).

patch_data(_) ->
    Headers = [{<<"Content-Type">>, <<"application/json">>}],
    {ok, #{status := 200, body := Body}} =
        katipo:patch(?POOL, <<"http://httpbin.org/patch">>,
                   #{headers => Headers, body => <<"!@#$%^&*()">>}),
    Json = jsx:decode(Body),
    <<"!@#$%^&*()">> = proplists:get_value(<<"data">>, Json).

patch_arity_2(_) ->
    {ok, #{status := 200, body := Body}} =
        katipo:patch(?POOL, <<"http://httpbin.org/patch">>),
    Json = jsx:decode(Body),
    <<>> = proplists:get_value(<<"data">>, Json).

patch_qs(_) ->
    QsVals = [{<<"foo">>, <<"bar">>}, {<<"baz">>, true}],
    {ok, #{status := 200, body := Body}} =
        katipo:patch(?POOL, <<"http://httpbin.org/patch">>, #{body => QsVals}),
    Json = jsx:decode(Body),
    [] = [{<<"baz">>,<<>>},{<<"foo">>,<<"bar">>}] -- proplists:get_value(<<"form">>, Json).

options(_) ->
    {ok, #{status := 200, headers := Headers}} = katipo:options(?POOL, <<"http://httpbin.org">>),
    <<"GET, POST, PUT, DELETE, PATCH, OPTIONS">> =
        proplists:get_value(<<"Access-Control-Allow-Methods">>, Headers).

delete(_) ->
    {ok, #{status := 200}} = katipo:delete(?POOL, <<"http://httpbin.org/delete">>).

headers(_) ->
    Headers = [{<<"header1">>, <<"!@#$%^&*()">>}],
    {ok, #{status := 200, body := Body}} =
        katipo:get(?POOL, <<"http://httpbin.org/gzip">>, #{headers => Headers}),
    Json = jsx:decode(Body),
    Expected =  [{<<"Accept">>,<<"*/*">>},
                 {<<"Accept-Encoding">>,<<"gzip,deflate">>},
                 {<<"Header1">>,<<"!@#$%^&*()">>},
                 {<<"Host">>,<<"httpbin.org">>}],
    [] = Expected -- proplists:get_value(<<"headers">>, Json).

header_remove(_) ->
    Headers = [{<<"Accept-Encoding">>, <<>>}],
    {ok, #{status := 200, body := Body}} =
        katipo:get(?POOL, <<"http://httpbin.org/get">>, #{headers => Headers}),
    Json = jsx:decode(Body),
    Expected =  [{<<"Accept">>,<<"*/*">>},
                 {<<"Host">>,<<"httpbin.org">>}],
    [] = Expected -- proplists:get_value(<<"headers">>, Json).

gzip(_) ->
    {ok, #{status := 200, body := Body}} = katipo:get(?POOL, <<"http://httpbin.org/gzip">>),
    Json = jsx:decode(Body),
    true = proplists:get_value(<<"gzipped">>, Json).

deflate(_) ->
    {ok, #{status := 200, body := Body}} = katipo:get(?POOL, <<"http://httpbin.org/deflate">>),
    Json = jsx:decode(Body),
    true = proplists:get_value(<<"deflated">>, Json).

bytes(_) ->
    {ok, #{status := 200, body := Body}} = katipo:get(?POOL, <<"http://httpbin.org/bytes/1024?seed=9999">>),
    1024 = byte_size(Body),
    <<214,141,60,147,148,212,22,181,40,183,133,31,67,245,222,40>> = crypto:hash(md5, Body).

stream_bytes(_) ->
    {ok, #{status := 200, body := Body}} = katipo:get(?POOL, <<"http://httpbin.org/bytes/1024?seed=9999&chunk_size=8">>),
    1024 = byte_size(Body),
    <<214,141,60,147,148,212,22,181,40,183,133,31,67,245,222,40>> = crypto:hash(md5, Body).

utf8(_) ->
    {ok, #{status := 200, body := Body}} = katipo:get(?POOL, <<"http://httpbin.org/encoding/utf8">>),
    case xmerl_ucs:from_utf8(Body) of
        [_|_] -> ok
    end.

stream(_) ->
    {ok, #{status := 200, body := Body}} = katipo:get(?POOL, <<"http://httpbin.org/stream/20">>),
    20 = length(binary:split(Body, <<"\n">>, [global, trim])).

statuses(_) ->
    MFAs = [begin
                B = integer_to_binary(S),
                Url = <<"http://httpbin.org/status/",B/binary>>,
                {katipo, get, [?POOL, Url]}
            end || S <- http_status_codes()],
    Results = rpc:parallel_eval(MFAs),
    Results2 = [S || {ok, #{status := S}} <- Results],
    Results2 = http_status_codes().

cookies(_) ->
    Url = <<"http://httpbin.org/cookies/set?cname=cvalue">>,
    Opts = #{followlocation => true},
    {ok, #{status := 200, cookiejar := CookieJar, body := Body}} = katipo:get(?POOL, Url, Opts),
    Json = jsx:decode(Body),
    [{<<"cname">>, <<"cvalue">>}] = proplists:get_value(<<"cookies">>, Json),
    [<<"httpbin.org\tFALSE\t/\tFALSE\t0\tcname\tcvalue">>] = CookieJar.

cookies_delete(_) ->
    Url = <<"http://httpbin.org/cookies/delete?cname">>,
    CookieJar = [<<"httpbin.org\tFALSE\t/\tFALSE\t0\tcname\tcvalue">>],
    {ok, #{status := 200, cookiejar := [_], body := Body}} =
        katipo:get(?POOL, Url, #{cookiejar => CookieJar, followlocation => true}),
    Json = jsx:decode(Body),
    [{}] = proplists:get_value(<<"cookies">>, Json).

cookies_bad_cookie_jar(_) ->
    Url = <<"http://httpbin.org/cookies/delete?cname">>,
    CookieJar = ["has to be a binary"],
    Message = <<"[{cookiejar,[\"has to be a binary\"]}]">>,
    {error, #{code := bad_opts, message := Message}} =
        katipo:get(?POOL, Url, #{cookiejar => CookieJar}).

%% TODO
redirect_to(_) ->
    {ok, #{status := 302}} = katipo:get(?POOL, <<"http://httpbin.org/redirect-to?url=https://google.com">>).

connecttimeout_ms(_) ->
    {error, #{code := operation_timedout}} =
        katipo:get(?POOL, <<"http://google.com">>, #{connecttimeout_ms => 1}).

followlocation_true(_) ->
    {ok, #{status := 200, headers := Headers}} =
        katipo:get(?POOL, <<"http://httpbin.org/redirect/6">>, #{followlocation => true}),
    1 = length(proplists:get_all_values(<<"Server">>, Headers)).

followlocation_false(_) ->
    {ok, #{status := 302}} =
        katipo:get(?POOL, <<"http://httpbin.org/redirect/6">>, #{followlocation => false}).

tcp_fastopen_true(_) ->
    {ok, #{}} =
        katipo:get(?POOL, <<"http://httpbin.org/get">>, #{tcp_fastopen => true}).

tcp_fastopen_false(_) ->
    {ok, #{}} =
        katipo:get(?POOL, <<"http://httpbin.org/get">>, #{tcp_fastopen => false}).

maxredirs(_) ->
    Opts = #{followlocation => true, maxredirs => 2},
    {error, #{code := too_many_redirects, message := <<"Maximum (2) redirects followed">>}} =
        katipo:get(?POOL, <<"http://httpbin.org/redirect/6">>, Opts).

basic_unauthorised(_) ->
    {ok, #{status := 401}} =
        katipo:get(?POOL, <<"http://httpbin.org/basic-auth/johndoe/p455w0rd">>).

basic_authorised(_) ->
    Username = <<"johndoe">>,
    Password = <<"p455w0rd">>,
    {ok, #{status := 200, body := Body}} =
        katipo:get(?POOL, <<"http://httpbin.org/basic-auth/johndoe/p455w0rd">>,
                  #{http_auth => basic, username => Username, password => Password}),
    Json = jsx:decode(Body),
    true = proplists:get_value(<<"authenticated">>, Json),
    Username = proplists:get_value(<<"user">>, Json).

digest_unauthorised(_) ->
    {ok, #{status := 401}} =
        katipo:get(?POOL, <<"http://httpbin.org/digest-auth/auth/johndoe/p455w0rd">>).

digest_authorised(_) ->
    Username = <<"johndoe">>,
    Password = <<"p455w0rd">>,
    {ok, #{status := 200, body := Body}} =
        katipo:get(?POOL, <<"http://httpbin.org/digest-auth/auth/johndoe/p455w0rd">>,
                  #{http_auth => digest, username => Username, password => Password}),
    Json = jsx:decode(Body),
    true = proplists:get_value(<<"authenticated">>, Json),
    Username = proplists:get_value(<<"user">>, Json).

badopts(_) ->
    {error, #{code := bad_opts, message := Message}} =
        katipo:get(?POOL, <<"http://httpbin.org/get">>, #{timeout_ms => <<"wrong">>, what => not_even_close}),
    {ok, Tokens, _} = erl_scan:string(binary_to_list(Message) ++ "."),
    {ok, L} = erl_parse:parse_term(Tokens),
    [] = L -- [{what, not_even_close}, {timeout_ms, <<"wrong">>}].

proxy_couldnt_connect(_) ->
    Url = <<"http://httpbin.org/get">>,
    {error, #{code := couldnt_connect}} =
        katipo:get(?POOL, Url, #{proxy => <<"http://localhost:3128">>}).

timeout_ms(_) ->
    {error, #{code := operation_timedout}} =
        katipo:get(?POOL, <<"http://httpbin.org/delay/1">>, #{timeout_ms => 500}).

couldnt_resolve_host(_) ->
    {error, #{code := couldnt_resolve_host,
              message := <<"Couldn't resolve host 'abadhostnamethatdoesnotexist'">>}} =
        katipo:get(?POOL, <<"http://abadhostnamethatdoesnotexist">>).

http_status_codes() ->
    [200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301,
     302, 303, 304, 305, 306, 307, 308,
     400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414,
     415, 416, 417, 421, 422, 423, 424, 426, 428, 429, 431,
     500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511].

pool_start_stop(_) ->
    PoolName = start_stop_pool,
    PoolSize = 2,
    {ok, Pid} = katipo_pool:start(PoolName, PoolSize, []),
    ok = katipo_pool:stop(PoolName),
    receive
    after 2500 ->
            ok
    end,
    {ok, Pid2} = katipo_pool:start(PoolName, PoolSize, []),
    ok = katipo_pool:stop(PoolName),
    true = Pid =/= Pid2.

active_workers() ->
    Pids = [begin
                Name = lists:flatten(io_lib:format("wpool_pool-~s-~B", [?POOL, N])),
                NameAtom = list_to_existing_atom(Name),
                whereis(NameAtom)
            end || N <- lists:seq(1, ?POOL_SIZE)],
    [P || P <- Pids, P /= undefined].

worker_death(_) ->
    Active = active_workers(),
    _ = [exit(W, kill) || W <- Active],
    Fun = fun() ->
                  Active2 = active_workers(),
                  [] == Active2 -- (Active2 -- Active)
          end,
    true = repeat_until_true(Fun),
    Fun2 = fun() ->
                  length(Active) == length(active_workers())
          end,
    true = repeat_until_true(Fun2),
    Fun3 = fun() ->
                   {ok, #{status := 200}} = katipo:get(?POOL, <<"http://httpbin.org/get">>),
                   true
           end,
    true = repeat_until_true(Fun3).

port_death(_) ->
    PoolName = this_process_will_be_killed,
    PoolSize = 1,
    {ok, _} = katipo_pool:start(PoolName, PoolSize),
    WorkerName = wpool_pool:best_worker(PoolName),
    WorkerPid = whereis(WorkerName),
    {state, _, katipo, {state, Port, _}, _} = sys:get_state(WorkerPid),
    true = port_command(Port, <<"hdfjkshkjsdfgjsgafdjgsdjgfj">>),
    Fun = fun() ->
                  WorkerName2 = wpool_pool:best_worker(PoolName),
                  WorkerPid2 = whereis(WorkerName2),
                  case sys:get_state(WorkerPid2) of
                      {state, _, katipo, {state, Port2, _}, _} when Port =/= Port2 ->
                          {ok, #{status := 200}} =
                              katipo:get(PoolName, <<"http://httpbin.org/get">>),
                          true
                  end
          end,
    true = repeat_until_true(Fun).

port_late_response(_) ->
    ok = meck:new(katipo, [passthrough]),
    meck:expect(katipo, get_timeout, fun(_) -> 100 end),
    {error, #{code := operation_timedout, message := <<>>}} =
        katipo:get(?POOL, <<"http://httpbin.org/delay/1">>),
    meck:unload(katipo).

pool_opts(_) ->
    PoolName = pool_opts,
    PoolSize = 1,
    PoolOpts = [{pipelining, true},
                {max_pipeline_length, 5},
                {max_total_connections, 10},
                {ignore_junk_opt, hithere}],
    {ok, _} = katipo_pool:start(PoolName, PoolSize, PoolOpts),
    ok = katipo_pool:stop(PoolName).

verify_host_verify_peer_ok(_) ->
    Opts = [#{ssl_verifyhost => true, ssl_verifypeer => true},
            #{ssl_verifyhost => false, ssl_verifypeer => true},
            #{ssl_verifyhost => true, ssl_verifypeer => false},
            #{ssl_verifyhost => false, ssl_verifypeer => false}],
    [{ok, _} = katipo:get(?POOL, <<"https://google.com">>, O) || O <- Opts].

verify_host_verify_peer_error(_) ->
    {error, #{code := ssl_cacert}} =
         katipo:get(?POOL, <<"https://localhost:8443">>,
                    #{ssl_verifyhost => true, ssl_verifypeer => true}),
    {error, #{code := ssl_cacert}} =
         katipo:get(?POOL, <<"https://localhost:8443">>,
                    #{ssl_verifyhost => false, ssl_verifypeer => true}),
    {ok, #{status := 200}} =
        katipo:get(?POOL, <<"https://localhost:8443">>,
                   #{ssl_verifyhost => true, ssl_verifypeer => false}),
    {ok, #{status := 200}} =
        katipo:get(?POOL, <<"https://localhost:8443">>,
                   #{ssl_verifyhost => false, ssl_verifypeer => false}).

cacert_self_signed(Config) ->
    CACert = ?config(cacert_file, Config),
    {ok, #{status := 200}} =
        katipo:get(?POOL, <<"https://localhost:8443">>,
                   #{ssl_verifyhost => true, ssl_verifypeer => true, cacert => CACert}).

proxy_get(_) ->
    Url = <<"http://httpbin.org/get?a=%21%40%23%24%25%5E%26%2A%28%29_%2B">>,
    {ok, #{status := 200, body := Body}} =
        katipo:get(?POOL, Url, #{proxy => <<"http://localhost:3128">>}),
    Json = jsx:decode(Body),
    [{<<"a">>, <<"!@#$%^&*()_+">>}] = proplists:get_value(<<"args">>, Json).

proxy_post_data(_) ->
    Url = <<"http://httpbin.org/post">>,
    {ok, #{status := 200, body := Body}} =
        katipo:post(?POOL, Url,
                    #{headers => [{<<"Content-Type">>, <<"application/json">>}],
                      body => <<"!@#$%^&*()">>,
                      proxy => <<"http://localhost:3128">>}),
    Json = jsx:decode(Body),
    <<"!@#$%^&*()">> = proplists:get_value(<<"data">>, Json).

%% session

session_new(_) ->
    {ok, Session} = katipo_session:new(?POOL),
    Url = <<"http://httpbin.org/cookies/set?cname=cvalue">>,
    Req = #{url => Url, followlocation => true},
    {{ok, #{status := 200, cookiejar := CookieJar, body := Body}}, Session2} =
        katipo_session:req(Req, Session),
    {state, ?POOL, #{cookiejar := CookieJar}} = Session2,
    Json = jsx:decode(Body),
    [{<<"cname">>, <<"cvalue">>}] = proplists:get_value(<<"cookies">>, Json),
    [<<"httpbin.org\tFALSE\t/\tFALSE\t0\tcname\tcvalue">>] = CookieJar.

session_new_bad_opts(_) ->
    {error, #{code := bad_opts}} =
        katipo_session:new(?POOL, #{timeout_ms => <<"wrong">>, what => not_even_close}).

session_new_cookies(_) ->
    Url = <<"http://httpbin.org/cookies/delete?cname">>,
    CookieJar = [<<"httpbin.org\tFALSE\t/\tFALSE\t0\tcname\tcvalue">>,
                 <<"httpbin.org\tFALSE\t/\tFALSE\t0\tcname2\tcvalue2">>],
    Req = #{url => Url, cookiejar => CookieJar, followlocation => true},
    {ok, Session} = katipo_session:new(?POOL, Req),
    {{ok, #{status := 200, body := Body}}, Session2} =
        katipo_session:req(#{}, Session),
    Json = jsx:decode(Body),
    [{<<"cname2">>, <<"cvalue2">>}] = proplists:get_value(<<"cookies">>, Json),
    Url2 = <<"http://httpbin.org/cookies/delete?cname2">>,
    {{ok, #{status := 200, body := Body2}}, _} =
        katipo_session:req(#{url => Url2}, Session2),
    Json2 = jsx:decode(Body2),
    [{}] = proplists:get_value(<<"cookies">>, Json2).

session_new_headers(_) ->
    Req = #{url => <<"http://httpbin.org/cookies/delete?cname">>,
            headers => [{<<"header1">>, <<"dontcare">>}]},
    {ok, Session} = katipo_session:new(?POOL, Req),
    {{ok, #{status := 200, body := Body}}, _Session2} =
        katipo_session:req(#{url => <<"http://httpbin.org/gzip">>,
                             headers => [{<<"header1">>, <<"!@#$%^&*()">>}]},
                           Session),
    Json = jsx:decode(Body),
    Expected =  [{<<"Accept">>,<<"*/*">>},
                 {<<"Accept-Encoding">>,<<"gzip,deflate">>},
                 {<<"Header1">>,<<"!@#$%^&*()">>},
                 {<<"Host">>,<<"httpbin.org">>}],
    [] = Expected -- proplists:get_value(<<"headers">>, Json).

session_update(_) ->
    Req = #{url => <<"http://httpbin.org/cookies/delete?cname">>,
            headers => [{<<"header1">>, <<"dontcare">>}]},
    {ok, Session} = katipo_session:new(?POOL, Req),
    Req2 = #{url => <<"http://httpbin.org/gzip">>,
             headers => [{<<"header1">>, <<"!@#$%^&*()">>}]},
    {ok, Session2} = katipo_session:update(Req2, Session),
    {{ok, #{status := 200, body := Body}}, _Session3} =
        katipo_session:req(#{}, Session2),
    Json = jsx:decode(Body),
    Expected =  [{<<"Accept">>,<<"*/*">>},
                 {<<"Accept-Encoding">>,<<"gzip,deflate">>},
                 {<<"Header1">>,<<"!@#$%^&*()">>},
                 {<<"Host">>,<<"httpbin.org">>}],
    [] = Expected -- proplists:get_value(<<"headers">>, Json).

session_update_bad_opts(_) ->
    {ok, Session} = katipo_session:new(?POOL),
    {error, #{code := bad_opts}} =
        katipo_session:update(#{timeout_ms => <<"wrong">>, what => not_even_close}, Session).

max_total_connections(_) ->
    PoolName = max_total_connections,
    {ok, _} = katipo_pool:start(PoolName, 1, [{max_total_connections, 1}]),
    Self = self(),
    Fun = fun() ->
                  {ok, #{status := 200}} =
                      katipo:get(PoolName, <<"http://httpbin.org/delay/5">>),
                  Self ! ok
          end,
    spawn(Fun),
    spawn(Fun),
    Start = erlang:system_time(seconds),
    [receive ok -> ok end || _ <- [1, 2]],
    Diff = erlang:system_time(seconds) - Start,
    true = Diff >= 10.

metrics_true(_) ->
    ok = meck:new(metrics, [passthrough]),
    ok = meck:expect(metrics, update_histogram,
                     fun(_, X, _) when X =:= <<"katipo.total_time">> orelse
                                       X =:= <<"katipo.curl_time">> orelse
                                       X =:= <<"katipo.namelookup_time">> orelse
                                       X =:= <<"katipo.connect_time">> orelse
                                       X =:= <<"katipo.appconnect_time">> orelse
                                       X =:= <<"katipo.pretransfer_time">> orelse
                                       X =:= <<"katipo.redirect_time">> orelse
                                       X =:= <<"katipo.starttransfer_time">> ->
                             ok
                     end),
    {ok, #{status := 200, metrics := Metrics}} =
        katipo:head(?POOL, <<"http://httpbin.org/get">>, #{return_metrics => true}),
    8 = meck:num_calls(metrics, update_histogram, 3),
    MetricKeys = [K || {K, _} <- Metrics],
    ExpectedMetricKeys = [curl_time,total_time,namelookup_time,connect_time,
                          appconnect_time,pretransfer_time,redirect_time,
                          starttransfer_time],
    true = lists:sort(MetricKeys) == lists:sort(ExpectedMetricKeys),
    meck:unload(metrics).

metrics_false(_) ->
    {ok, #{status := 200} = Res} =
        katipo:head(?POOL, <<"http://httpbin.org/get">>, #{return_metrics => false}),
    false = maps:is_key(metrics, Res).

repeat_until_true(Fun) ->
    try
        case Fun() of
            true ->
                true;
            _ ->
                timer:sleep(100),
                repeat_until_true(Fun)
        end
    catch _:_ ->
            timer:sleep(100),
            repeat_until_true(Fun)
    end.
