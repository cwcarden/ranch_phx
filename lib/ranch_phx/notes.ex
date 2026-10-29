defmodule RanchPhx.Notes do
  @moduledoc """
  Handwritten notes for each animal: pages written with the Pencil, filed by date and
  topic, with the words read off the page by the AI (or typed) so they can be searched.
  """
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.Notes.Note

  @labels %{
    "general" => "General",
    "health" => "Health",
    "training" => "Training",
    "feeding" => "Feeding",
    "farrier" => "Farrier",
    "breeding" => "Breeding",
    "ideas" => "Ideas"
  }

  def topics, do: Enum.map(Note.topics(), &{&1, @labels[&1]})
  def topic_label(t), do: @labels[t] || "General"

  @doc "An animal's notes, newest first; optionally one topic and words to look for."
  def list(animal_id, opts \\ []) do
    Note
    |> where([n], n.animal_id == ^animal_id)
    |> then(fn q ->
      case opts[:topic] do
        t when t in [nil, "", "all"] -> q
        t -> where(q, [n], n.topic == ^t)
      end
    end)
    |> then(fn q ->
      case opts[:q] |> to_string() |> String.trim() do
        "" ->
          q

        words ->
          like = "%" <> String.replace(words, ~r/[%_\\]/, "") <> "%"
          where(q, [n], ilike(n.text, ^like) or ilike(n.title, ^like))
      end
    end)
    |> order_by([n], desc: n.date, desc: n.id)
    |> Repo.all()
  end

  def get(animal_id, id), do: Repo.get_by(Note, id: id, animal_id: animal_id)

  def create(attrs), do: %Note{} |> Note.changeset(attrs) |> Repo.insert()
  def update(%Note{} = n, attrs), do: n |> Note.changeset(attrs) |> Repo.update()
  def delete(%Note{} = n), do: Repo.delete(n)

  def count(animal_id),
    do: Repo.aggregate(from(n in Note, where: n.animal_id == ^animal_id), :count)

  def latest(animal_id),
    do:
      Repo.one(
        from n in Note,
          where: n.animal_id == ^animal_id,
          order_by: [desc: n.date, desc: n.id],
          limit: 1
      )
end
