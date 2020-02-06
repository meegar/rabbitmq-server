%%%-------------------------------------------------------------------
%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at https://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% Copyright (c) 2019-2020 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_boot_state).

-include_lib("eunit/include/eunit.hrl").

-export([get/0,
         set/1,
         wait_for/1]).

-define(PT_KEY_BOOT_STATE,    {?MODULE, boot_state}).

-type boot_state() :: 'stopped' | 'booting' | 'ready' | 'stopping'.

-export_type([boot_state/0]).

-spec get() -> boot_state().
get() ->
    persistent_term:get(?PT_KEY_BOOT_STATE, stopped).

-spec set(boot_state()) -> ok.
set(BootState) ->
    rabbit_log_prelaunch:debug("Change boot state to `~s`", [BootState]),
    ?assert(is_boot_state_valid(BootState)),
    case BootState of
        stopped -> persistent_term:erase(?PT_KEY_BOOT_STATE);
        _       -> persistent_term:put(?PT_KEY_BOOT_STATE, BootState)
    end,
    notify_boot_state_listeners(BootState).

-spec wait_for(boot_state()) -> ok | {error, timeout}.
wait_for(BootState) ->
    ?assert(is_boot_state_valid(BootState)),
    wait_for_boot_state(BootState, infinity).

wait_for_boot_state(BootState, infinity = Timeout) ->
    case is_boot_state_reached(BootState) of
        true  -> ok;
        false -> wait_for_boot_state(BootState, Timeout)
    end;
wait_for_boot_state(BootState, Timeout)
    when is_integer(Timeout) andalso Timeout >= 0 ->
    case is_boot_state_reached(BootState) of
        true  -> ok;
        false -> Wait = 200,
            timer:sleep(Wait),
            wait_for_boot_state(BootState, Timeout - Wait)
    end;
wait_for_boot_state(_, _) ->
    {error, timeout}.

boot_state_idx(stopped)  -> 0;
boot_state_idx(booting)  -> 1;
boot_state_idx(ready)    -> 2;
boot_state_idx(stopping) -> 3;
boot_state_idx(_)        -> undefined.

is_boot_state_valid(BootState) ->
    is_integer(boot_state_idx(BootState)).

is_boot_state_reached(TargetBootState) ->
    is_boot_state_reached(?MODULE:get(), TargetBootState).

is_boot_state_reached(CurrentBootState, CurrentBootState) ->
    true;
is_boot_state_reached(stopping, stopped) ->
    false;
is_boot_state_reached(_CurrentBootState, stopped) ->
    true;
is_boot_state_reached(stopped, _TargetBootState) ->
    true;
is_boot_state_reached(CurrentBootState, TargetBootState) ->
    boot_state_idx(TargetBootState) =< boot_state_idx(CurrentBootState).

notify_boot_state_listeners(BootState) ->
    lists:foreach(fun(Child) ->
                          gen_server:cast(Child, {notify_boot_state, BootState})
                  end,
                  rabbit_boot_state_sup:child_pids()).
