defmodule RanchPhx.VoiceNotes do
  @moduledoc """
  Notes said to Siri with the "Ranch log" Shortcut. Each lands here as pending, tied to
  the animal it names, and waits until it's checked and saved as records (or dismissed).
  Nothing becomes a record without a look first.
  """
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.Animals.Animal
  alias RanchPhx.VoiceNotes.VoiceNote

  @doc """
  Saves what was said, one note per animal it names (or one with no animal when it
  names none). Returns `{:ok, notes}` or `{:error, :empty}`.
  """
  def create_from_text(user, text) do
    text = text |> to_string() |> String.trim()

    if text == "" do
      {:error, :empty}
    else
      animals = Repo.all(from a in Animal, where: a.owned == true, order_by: a.name)

      ids =
        case match_animals(text, animals) do
          [] -> [nil]
          found -> Enum.map(found, & &1.id)
        end

      notes =
        for id <- ids do
          %VoiceNote{}
          |> VoiceNote.changeset(%{text: text, animal_id: id, user_id: user && user.id})
          |> Repo.insert!()
          |> Repo.preload(:animal)
        end

      broadcast()
      {:ok, notes}
    end
  end

  @doc """
  Animals named in `text`: by full name, barn name ("Asher"), or by first name when
  only one animal has it.
  Active animals win over retired, sold or deceased ones with the same name.
  """
  def match_animals(text, animals) do
    said = normalize(text)
    has? = fn name -> name != "" and String.contains?(" #{said} ", " #{normalize(name)} ") end

    firsts =
      animals
      |> Enum.map(&first_name/1)
      |> Enum.frequencies()

    animals
    |> Enum.filter(fn a ->
      has?.(a.name) or (is_binary(Map.get(a, :barn_name)) and has?.(a.barn_name)) or
        (firsts[first_name(a)] == 1 and String.length(first_name(a)) >= 3 and has?.(first_name(a)))
    end)
    |> prefer_active()
  end

  defp prefer_active(found) do
    active = Enum.filter(found, &(&1.status == "active"))
    if active == [], do: found, else: active
  end

  defp first_name(%{name: name}), do: name |> to_string() |> String.split() |> List.first("")

  defp normalize(s),
    do:
      s
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/['’]s\b/u, "")
      |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
      |> String.trim()

  def list_pending do
    Repo.all(
      from n in VoiceNote,
        where: n.status == "pending",
        order_by: [desc: n.inserted_at],
        preload: :animal
    )
  end

  def count_pending,
    do: Repo.aggregate(from(n in VoiceNote, where: n.status == "pending"), :count)

  def get(id), do: VoiceNote |> Repo.get(id) |> Repo.preload(:animal)

  def set_animal(%VoiceNote{} = note, animal_id) do
    note
    |> VoiceNote.changeset(%{animal_id: animal_id})
    |> Repo.update()
    |> tap(fn _ -> broadcast() end)
  end

  def mark(%VoiceNote{} = note, status) when status in ~w(done dismissed) do
    note
    |> VoiceNote.changeset(%{status: status})
    |> Repo.update()
    |> tap(fn _ -> broadcast() end)
  end

  @topic "voice_notes"
  def subscribe, do: Phoenix.PubSub.subscribe(RanchPhx.PubSub, @topic)
  defp broadcast, do: Phoenix.PubSub.broadcast(RanchPhx.PubSub, @topic, :voice_notes_changed)
end
