-module(mxpak_ffi).
-export([get_arguments/0, ensure_apps_started/0, kill_zombie_chrome/0, get_home_dir/0, make_hard_link/2]).

%% init:get_plain_arguments()는 gleam run에서는 charlist,
%% escript에서는 binary를 반환할 수 있음. 양쪽 모두 처리.
get_arguments() ->
    [to_binary(A) || A <- init:get_plain_arguments()].

to_binary(A) when is_binary(A) -> A;
to_binary(A) when is_list(A) ->
    case unicode:characters_to_binary(A) of
        Bin when is_binary(Bin) -> Bin;
        _ -> <<>>
    end;
to_binary(_) -> <<>>.

%% chrobot_extra가 WebSocket 트랜스포트 사용 시 필요한 OTP 앱 시작
ensure_apps_started() ->
    {ok, _} = application:ensure_all_started(gun),
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(ssl),
    nil.

%% 홈 디렉토리 반환
get_home_dir() ->
    case os:getenv("HOME") of
        false ->
            case os:getenv("USERPROFILE") of
                false -> {error, nil};
                Path -> {ok, unicode:characters_to_binary(Path)}
            end;
        Path -> {ok, unicode:characters_to_binary(Path)}
    end.

%% 하드 링크 생성 (같은 볼륨에서만 동작, 실패 시 Gleam 측에서 복사 폴백)
make_hard_link(Existing, New) ->
    case file:make_link(binary_to_list(Existing), binary_to_list(New)) of
        ok -> {ok, nil};
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% chrobot-ws-profile lockfile을 잡고 있는 좀비 Chrome 강제 종료
kill_zombie_chrome() ->
    case os:type() of
        {win32, _} ->
            os:cmd("cmd /c \"taskkill /F /IM chrome.exe\" 2>nul"),
            timer:sleep(1000);
        _ ->
            os:cmd("pkill -f chrobot-ws-profile 2>/dev/null"),
            timer:sleep(500)
    end,
    nil.
