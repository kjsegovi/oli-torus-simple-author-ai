defmodule Oli.GoogleSlides.Util do
  @moduledoc false

  @spec new_id(String.t()) :: String.t()
  def new_id(prefix \\ "id") do
    "#{prefix}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  @spec new_rule_id() :: String.t()
  def new_rule_id, do: "r:#{UUID.uuid4()}"

  @spec deck_group_id() :: String.t()
  def deck_group_id, do: Integer.to_string(System.system_time(:millisecond))
end
