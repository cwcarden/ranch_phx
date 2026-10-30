defmodule RanchPhx.Repo.Migrations.SurcingleGroundDriving do
  use Ecto.Migration

  # Ground driving starts in a training surcingle (lines through the low side
  # rings, nothing on his loin), and switches to the saddle with stirrups tied
  # low around mid-March, so he's driven in full tack before the first ride.
  # Stages are updated by name; session types are left as they are.

  @program "colt_start_cow_horse"

  # {name, summary, focus, guardrail}
  defp stages do
    [
      {"Saddle & pad", "Make the saddle boring before anything else is asked of him.",
       [
         "Pad, then saddle, from both sides",
         "Cinch up in stages; walk him between each tightening",
         "Lead him around saddled; let the stirrups bump him",
         "Rub the stirrups and fenders all over him",
         "Introduce the training surcingle the same way: behind the withers, snug in stages, lead and longe in it",
         "Flag work and free longeing in the round pen",
         "Stand tied saddled, building toward an hour"
       ],
       "Start at 15–20 min saddled, work up to 30–45. Most days, not every day. Never walk him with the saddle uncinched. Check his back for even sweat after."},
      {"Saddling & ground driving",
       "Longe in the saddle and teach go, whoa and turn from behind, driving in the training surcingle and side-pull.",
       [
         "Longe saddled in big circles (50–60 ft or more on a line), mostly walk and trot",
         "Rub and drag the lines over his back, hindquarters and hind legs while he stands",
         "Ground drive in the training surcingle and side-pull: lines through the lowest side rings",
         "Go, whoa and easy turns both ways",
         "Stand back and to the side, out of kick range"
       ],
       "Keep circles big; growth plates are still closing. 5–10 min of actual moving or driving. Light pulls and quick releases. Use the low surcingle rings, never the top ones, so he learns to carry his head level. Save the bosal for riding."},
      {"Getting ready to ride", "Everything a rider will feel, except the rider.",
       [
         "Switch ground driving from the surcingle to the saddle, stirrups tied low under his belly",
         "Back cinch and hobble strap; breast collar",
         "Ground drive: stops, turns and backing",
         "Feed sacks tied on balanced, 20–30 lb to start",
         "Weight in the stirrup, lean over him, bounce beside him",
         "Fit and shape the bosal; let him wear it during groundwork",
         "Give to the bosal from the ground: bend each way, soft back-up"
       ],
       "Keep the feed-sack load balanced and well under rider weight. Watch his loin under the saddle skirts on turns. If he worries about anything new, go back a step and end on a good one."}
    ]
  end

  @switch_goal {"Switch ground driving to the saddle (stirrups tied low)", ~D[2027-03-15],
                "After a short refresher in the surcingle once the vet clears him. He should drive in full tack before the first ride."}

  @driving_goal "Start longeing saddled and ground driving in the side-pull"
  @driving_notes "Drive in the training surcingle (low side rings) and side-pull. Big circles, walk and trot. Lines on his legs at a standstill first."

  def up do
    case repo().query!("SELECT id FROM training_programs WHERE slug = $1", [@program]) do
      %{rows: [[program_id]]} ->
        update_stages(program_id)
        update_goals(program_id)

      _ ->
        :ok
    end
  end

  def down, do: :ok

  defp update_stages(program_id) do
    for {name, summary, focus, guardrail} <- stages() do
      repo().query!(
        "UPDATE training_stages
           SET summary = $3::text, focus = $4::varchar[], guardrail = $5::text,
               updated_at = now()
         WHERE program_id = $1::bigint AND name = $2::varchar",
        [program_id, name, summary, focus, guardrail]
      )
    end
  end

  # Only for Asher's active book, and only when exactly one matches.
  defp update_goals(program_id) do
    %{rows: rows} =
      repo().query!(
        "SELECT b.id FROM training_books b JOIN training_horses h ON h.id = b.horse_id
         WHERE b.program_id = $1::bigint AND b.status = 'active'
           AND (h.name ILIKE '%asher%' OR h.name ILIKE '%soldier cat%'
                OR h.name ILIKE '%smitty%' OR h.name ILIKE '%blacksmith%')",
        [program_id]
      )

    case rows do
      [[book_id]] ->
        repo().query!(
          "UPDATE training_goals SET notes = $3::text, updated_at = now()
           WHERE book_id = $1::bigint AND title = $2::varchar",
          [book_id, @driving_goal, @driving_notes]
        )

        {title, date, notes} = @switch_goal

        repo().query!(
          "INSERT INTO training_goals
             (book_id, title, target_date, notes, status, position, inserted_at, updated_at)
           SELECT $1::bigint, $2::varchar, $3::date, $4::text, 'active',
                  COALESCE((SELECT MAX(position) + 1 FROM training_goals WHERE book_id = $1::bigint), 0),
                  now(), now()
           WHERE NOT EXISTS
             (SELECT 1 FROM training_goals WHERE book_id = $1::bigint AND title = $2::varchar)",
          [book_id, title, date, notes]
        )

      _ ->
        :ok
    end
  end
end
