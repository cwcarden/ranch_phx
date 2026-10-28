defmodule RanchPhx.LocalTime do
  @moduledoc """
  Ranch time (US Central) without a time zone database: daylight time runs from the
  second Sunday of March to the first Sunday of November, changing at 2 a.m.
  """

  @doc "Now, as a NaiveDateTime in ranch time."
  def now(utc \\ DateTime.utc_now()),
    do: utc |> DateTime.add(offset(utc), :second) |> DateTime.to_naive()

  def today(utc \\ DateTime.utc_now()), do: utc |> now() |> NaiveDateTime.to_date()

  def offset(%DateTime{year: y} = dt) do
    start = y |> nth_sunday(3, 2) |> DateTime.new!(~T[08:00:00], "Etc/UTC")
    stop = y |> nth_sunday(11, 1) |> DateTime.new!(~T[07:00:00], "Etc/UTC")
    dst? = DateTime.compare(dt, start) != :lt and DateTime.compare(dt, stop) == :lt
    if dst?, do: -5 * 3600, else: -6 * 3600
  end

  defp nth_sunday(year, month, n) do
    first = Date.new!(year, month, 1)
    Date.add(first, rem(7 - Date.day_of_week(first) + 7, 7) + (n - 1) * 7)
  end
end
