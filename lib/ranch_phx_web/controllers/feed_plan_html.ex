defmodule RanchPhxWeb.FeedPlanHTML do
  use RanchPhxWeb, :html
  alias RanchPhx.FeedPlans

  embed_templates "feed_plan_html/*"

  @colors [
    {"#f1f5ef", "#d5dfd1"},
    {"#fbf4e6", "#ecdcb6"},
    {"#f2f0f8", "#dcd6ec"},
    {"#eef5fa", "#cfe0ec"},
    {"#f9efec", "#ecd2ca"}
  ]

  def colors(i), do: Enum.at(@colors, rem(i, length(@colors)))

  def lines(body), do: FeedPlans.lines(body)

  # Phone numbers in contacts become tap-to-call links.
  def with_phone_links(text) do
    parts =
      Regex.split(~r/((?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4})/, text,
        include_captures: true
      )

    Enum.map(parts, fn part ->
      if Regex.match?(~r/^(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}$/, part) do
        digits = String.replace(part, ~r/[^\d+]/, "")
        {:phone, part, digits}
      else
        {:text, part}
      end
    end)
  end
end
