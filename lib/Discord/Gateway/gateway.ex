defmodule Alchemy.Discord.Gateway do
  @moduledoc false
  @behaviour :websocket_client
  alias Alchemy.Discord.Gateway.Manager
  import Alchemy.Discord.Payloads
  import Alchemy.Discord.Protocol
  require Logger


  defmodule State do
    @moduledoc false
    defstruct [:token, :shard, :trace, :session_id, :seq]
  end


  # Requests a gateway URL, before then connecting, and storing the token
  def start_link(token, shard) do
     :crypto.start
     :ssl.start
     # request_url will return a protocol to execute
     url = Manager.request_url().()
     :websocket_client.start_link(url, __MODULE__, %State{token: token, shard: shard})
  end


  def init(state) do
    {:once, state}
  end


  def onconnect(_ws_req, state) do
    Logger.debug "Shard #{Macro.to_string state.shard} Connected to the gateway"
    {:ok, state}
  end


  def ondisconnect(reason, state) do
    {:reconnect, state}
  end


  # Messages are either raw, or compressed JSON
  def websocket_handle({:binary, msg}, _conn_state, state) do
      msg |> :zlib.uncompress |> Poison.Parser.parse! |> dispatch(state)
  end
  def websocket_handle({:text, msg}, _conn_state, state) do
      msg |> Poison.Parser.parse! |> dispatch(state)
  end


  # Heartbeats need to be sent every interval
  def websocket_info({:heartbeat, interval}, _conn_state, state) do
    Process.send_after(self(), {:heartbeat, interval}, interval)
    {:reply, {:text, heartbeat(state.seq)}, state}
  end


  # Send the identify package to discord, if this is our fist session
  def websocket_info(:identify, _, %State{session_id: nil} = state) do
    this_shard = state.shard
    identify = identify_msg(state.token, this_shard)
    Process.send_after(GatewayManager, {:next_shard, this_shard}, 5000)
    {:reply, {:text, identify}, state}
  end
  # We can resume if we already have a session_id (i.e. we disconnected)
  def websocket_info(:identify, _, state) do
     {:reply, {:text, resume_msg(state)}, state}
  end


  def websocket_terminate(why, _conn_state, state) do
    Logger.debug "Websocket terminated, reason: #{Macro.to_string why}"
    :ok
  end

end
