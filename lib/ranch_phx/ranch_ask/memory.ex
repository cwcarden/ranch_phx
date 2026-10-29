defmodule RanchPhx.RanchAsk.Memory do
  @moduledoc """
  What was just asked through Siri, per person, for about ten minutes, so a follow-up
  ("what if that doesn't work?") keeps the thread and stays on the same animal. Lives
  in memory only; a restart simply starts fresh.
  """
  use Agent

  @keep_seconds 10 * 60
  @turns 4

  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "The recent conversation for `user_id`: `%{turns: [{q, a}], animal_ids: [...], threads: %{book_id => id}}`."
  def recall(nil), do: empty()

  def recall(user_id) do
    if Process.whereis(__MODULE__) do
      Agent.get(__MODULE__, fn m -> current(m[user_id]) end)
    else
      empty()
    end
  end

  @doc "Adds a question and its answer to `user_id`'s conversation."
  def remember(nil, _q, _a, _ids, _threads), do: :ok

  def remember(user_id, question, answer, animal_ids, threads) do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn m ->
        convo = current(m[user_id])

        m
        |> Map.reject(fn {_, c} -> not fresh?(c.at) end)
        |> Map.put(user_id, %{
          at: System.monotonic_time(:second),
          turns: Enum.take(convo.turns ++ [{question, answer}], -@turns),
          animal_ids: animal_ids,
          threads: Map.merge(convo.threads, threads)
        })
      end)
    end

    :ok
  end

  @doc false
  def forget_all, do: if(Process.whereis(__MODULE__), do: Agent.update(__MODULE__, fn _ -> %{} end))

  defp current(%{at: at} = convo), do: if(fresh?(at), do: convo, else: empty())
  defp current(_), do: empty()

  defp empty, do: %{turns: [], animal_ids: [], threads: %{}, at: nil}
  defp fresh?(nil), do: false
  defp fresh?(at), do: System.monotonic_time(:second) - at < @keep_seconds
end
