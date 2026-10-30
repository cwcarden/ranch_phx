defmodule RanchPhx.Repo.Migrations.AddVoiceCuesToStages do
  use Ecto.Migration

  # Voice cues, added to each stage's focus list so they show on the Stage card,
  # in the Timeline's stage view, and to the TrAIner.
  #
  # The set: cluck = walk on (later, trot), kiss = lope (once riding),
  # whoa = stop (said once), back = back up, easy = slow down / settle,
  # stand = stay put, over = move away, foot = pick up a hoof,
  # step up = into the trailer, whistle = come to me, good = right answer.
  #
  # Items are only appended when missing, so this is safe to run again.
  # (focus is varchar(255)[], so every item stays under 255 characters.)

  @program "colt_start_cow_horse"

  @items [
    {"Yearling groundwork & desensitizing",
     [
       "Voice cues: cluck = walk on, whoa = stop (say it once), back = back up, easy = slow down or settle (longe line, or when he's quick or worried), whistle = come to me",
       "Handling cues: stand = stay put (tying, saddling, mounting, ground tying), over = move his hip or shoulder away, foot = pick up a hoof (say it right before you ask), step up = into the trailer",
       "Say \"good\" softly the moment he gets something right, together with the release"
     ]},
    {"Saddle & pad",
     [
       "Voice cues every session: cluck to walk on, whoa once, back, easy on the longe line, stand while saddling, over, foot, step up, whistle to come, good when he gets it right",
       "Say each cue once, the same sound every time: low and calm for whoa and easy, bright for cluck"
     ]},
    {"Saddling & ground driving",
     [
       "Voice on the lines: cluck to walk on, whoa once then build line pressure and release the moment he stops, easy to slow, back with steady pressure"
     ]},
    {"Getting ready to ride",
     [
       "Voice for mounting prep: stand while you put weight in the stirrup; whoa, cluck, back and easy the same as on the lines"
     ]},
    {"Backing & first rides",
     [
       "Same voice cues from the saddle: cluck to walk and trot, whoa once, back, easy, each paired with your seat and the hackamore"
     ]},
    {"Foundation in the hackamore",
     ["Kiss for the lope. Start fading the voice so your seat and legs carry the cue"]},
    {"Cow work & maneuvers",
     ["Keep voice to a minimum; cues come from your seat, legs and hackamore"]},
    {"Show prep", ["Ride without relying on voice; save easy and whoa for schooling at home"]}
  ]

  def up do
    case repo().query!("SELECT id FROM training_programs WHERE slug = $1", [@program]) do
      %{rows: [[program_id]]} ->
        for {stage, items} <- @items, item <- items do
          repo().query!(
            "UPDATE training_stages
               SET focus = array_append(focus, $3::varchar), updated_at = now()
             WHERE program_id = $1::bigint AND name = $2::varchar
               AND NOT ($3::varchar = ANY(focus))",
            [program_id, stage, item]
          )
        end

      _ ->
        :ok
    end
  end

  def down, do: :ok
end
