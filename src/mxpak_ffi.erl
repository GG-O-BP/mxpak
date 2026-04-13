-module(mxpak_ffi).
-export([get_arguments/0, ensure_apps_started/0, kill_zombie_chrome/0, get_home_dir/0, make_hard_link/2, file_info/1, list_dir_recursive/2]).

%% init:get_plain_arguments()는 gleam run에서는 charlist,
%% escript에서는 binary를 반환할 수 있음. 양쪽 모두 처리.
%% Windows escript는 스크립트 경로를 첫 인자로 포함시키므로 제거.
get_arguments() ->
    Raw = init:get_plain_arguments(),
    Cleaned = strip_script_name(Raw),
    [to_binary(A) || A <- Cleaned].

strip_script_name([]) -> [];
strip_script_name([First | Rest] = All) ->
    try escript:script_name() of
        ScriptName ->
            FirstStr = case First of
                B when is_binary(B) -> binary_to_list(B);
                L when is_list(L) -> L
            end,
            case FirstStr =:= ScriptName of
                true -> Rest;
                false -> All
            end
    catch
        _:_ -> All
    end.

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

%% 파일 정보 (크기 + inode) — 하드링크 감지용
file_info(Path) ->
    case file:read_file_info(binary_to_list(Path)) of
        {ok, Info} ->
            Size = element(2, Info),
            Inode = element(9, Info),
            {ok, {Size, Inode}};
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% 재귀 파일 목록 — ExcludeDirs는 바이너리 리스트
list_dir_recursive(Dir, ExcludeDirs) ->
    case file:list_dir(binary_to_list(Dir)) of
        {ok, Entries} ->
            Files = lists:foldl(
                fun(EntryL, Acc) ->
                    Entry = unicode:characters_to_binary(EntryL),
                    Full = <<Dir/binary, <<"/">>/binary, Entry/binary>>,
                    case lists:member(Entry, ExcludeDirs) of
                        true -> Acc;
                        false ->
                            case filelib:is_dir(binary_to_list(Full)) of
                                true ->
                                    case list_dir_recursive(Full, ExcludeDirs) of
                                        {ok, Sub} -> Acc ++ Sub;
                                        _ -> Acc
                                    end;
                                false ->
                                    [Full | Acc]
                            end
                    end
                end,
                [],
                Entries
            ),
            {ok, Files};
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
