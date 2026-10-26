defmodule RanchPhx.Repo.Migrations.UpdateColtStartTimeline do
  use Ecto.Migration

  # Fills in the colt-start program between yearling groundwork and first rides
  # (saddle and pad at ~17 months, ground driving at 20, ready-to-ride prep at 22,
  # first rides at 24), and adds Asher's dated milestones to his book as goals.
  # Existing stages are updated in place so books pinned to a stage keep their pin.

  @program "colt_start_cow_horse"

  @ground ~w(handling groundwork flag feet trailer ponying other)
  @saddle @ground ++ ~w(saddling ground_driving)
  @ride @saddle ++ ~w(riding)

  # {name, from_age_months, summary, focus, guardrail, max_min, max_week, session_types}
  defp stages do
    [
      {"Saddle & pad", 17, "Make the saddle boring before anything else is asked of him.",
       [
         "Pad, then saddle, from both sides",
         "Cinch up in stages; walk him between each tightening",
         "Lead him around saddled; let the stirrups bump him",
         "Rub the stirrups and fenders all over him",
         "Flag work and free longeing in the round pen",
         "Stand tied saddled, building toward an hour"
       ],
       "Start at 15–20 min saddled, work up to 30–45. Most days, not every day. Never walk him with the saddle uncinched. Check his back for even sweat after.",
       30, 5, @saddle},
      {"Saddling & ground driving", 20,
       "Longe in the saddle and teach go, whoa and turn from behind, in the side-pull.",
       [
         "Longe saddled in big circles (50–60 ft pen), mostly walk and trot",
         "Rub and drag the lines over his back, hindquarters and hind legs while he stands",
         "Ground drive in the side-pull: lines through the stirrups, stirrups tied under his belly",
         "Go, whoa and easy turns both ways",
         "Stand back and to the side, out of kick range"
       ],
       "Keep circles big; growth plates are still closing. 5–10 min of actual moving or driving. Light pulls and quick releases. Save the bosal for riding.",
       25, 4, @saddle},
      {"Getting ready to ride", 22,
       "Everything a rider will feel, except the rider.",
       [
         "Back cinch and hobble strap; breast collar",
         "Ground drive: stops, turns and backing",
         "Feed sacks tied on balanced, 20–30 lb to start",
         "Weight in the stirrup, lean over him, bounce beside him",
         "Fit and shape the bosal; let him wear it during groundwork",
         "Give to the bosal from the ground: bend each way, soft back-up"
       ],
       "Keep the feed-sack load balanced and well under rider weight. If he worries about anything new, go back a step and end on a good one.",
       25, 4, @saddle},
      {"Backing & first rides", 24, "Light backing only, then lots of turnout.",
       [
         "First rides short, in the round pen, in the bosal",
         "Mount from both sides",
         "Walk, then trot",
         "Bend and give in the bosal like he learned on the ground",
         "One-rein stop",
         "Ride outside the pen"
       ],
       "Ride about 15–20 minutes, a few days a week, then turn out. Move him around a little before you get on. Rider weight matters at this age.",
       20, 3, @ride}
    ]
  end

  # {title, target_date, notes}
  defp goals do
    [
      {"World Show trip (OKC): saddled, round pen, standing tied", ~D[2026-11-12],
       "Saddle, lead and free longe in the round pen. If he's ready, rub the lines on him and take a few quiet driving steps. Tie solid to a pipe fence or a frame-bolted trailer ring, never a panel."},
      {"Start longeing saddled and ground driving in the side-pull", ~D[2027-01-04],
       "Big circles, walk and trot. Lines on his legs at a standstill first."},
      {"Gelding surgery", ~D[2027-02-15],
       "About two weeks to heal. Follow the vet's activity instructions; light handling only."},
      {"Back to groundwork once the vet clears him", ~D[2027-03-01],
       "Short refresher driving first. Start fitting the bosal."},
      {"Haul him to try colt saddles", ~D[2027-03-15],
       "Bring the 5 Star pad. Looking for a ranch cutter or cow horse saddle, semi-QH bars, about a 15.5\" seat. Write down the tree of whatever fits."},
      {"First ride in the bosal", ~D[2027-05-10], "Short, round pen. His second birthday."}
    ]
  end

  def up do
    case repo().query!("SELECT id FROM training_programs WHERE slug = $1", [@program]) do
      %{rows: [[program_id]]} ->
        update_stages(program_id)
        add_goals(program_id)

      _ ->
        :ok
    end
  end

  def down do
    case repo().query!("SELECT id FROM training_programs WHERE slug = $1", [@program]) do
      %{rows: [[program_id]]} ->
        repo().query!(
          "DELETE FROM training_stages WHERE program_id = $1 AND name = ANY($2)",
          [program_id, ["Saddle & pad", "Getting ready to ride"]]
        )

        renumber(program_id)

      _ ->
        :ok
    end
  end

  defp update_stages(program_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Move every stage out of the way of the unique (program_id, position) index.
    repo().query!(
      "UPDATE training_stages SET position = position + 1000 WHERE program_id = $1",
      [program_id]
    )

    stages()
    |> Enum.with_index()
    |> Enum.each(fn {{name, from, summary, focus, guardrail, max_min, max_week, types}, i} ->
      params = [program_id, name, from, summary, focus, guardrail, max_min, max_week, types, now]

      %{num_rows: updated} =
        repo().query!(
          "UPDATE training_stages
             SET from_age_months = $3, summary = $4, focus = $5, guardrail = $6,
                 max_session_minutes = $7, max_sessions_per_week = $8,
                 session_types = $9, updated_at = $10
           WHERE program_id = $1 AND name = $2",
          params
        )

      if updated == 0 do
        repo().query!(
          "INSERT INTO training_stages
             (program_id, name, from_age_months, summary, focus, guardrail,
              max_session_minutes, max_sessions_per_week, session_types,
              inserted_at, updated_at, position)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10, $11)",
          params ++ [2000 + i]
        )
      end
    end)

    renumber(program_id)
  end

  # Positions follow age: 0, 1, 2… ordered by from_age_months, ties kept in order.
  defp renumber(program_id) do
    repo().query!(
      "UPDATE training_stages SET position = position + 10000 WHERE program_id = $1",
      [program_id]
    )

    repo().query!(
      "UPDATE training_stages s SET position = r.rn - 1
       FROM (SELECT id, row_number() OVER (ORDER BY from_age_months, position) AS rn
             FROM training_stages WHERE program_id = $1) r
       WHERE s.id = r.id",
      [program_id]
    )
  end

  # Only when exactly one active book on this program belongs to Asher.
  defp add_goals(program_id) do
    %{rows: rows} =
      repo().query!(
        "SELECT b.id FROM training_books b JOIN training_horses h ON h.id = b.horse_id
         WHERE b.program_id = $1 AND b.status = 'active'
           AND (h.name ILIKE '%asher%' OR h.name ILIKE '%soldier cat%'
                OR h.name ILIKE '%smitty%' OR h.name ILIKE '%blacksmith%')",
        [program_id]
      )

    case rows do
      [[book_id]] -> insert_goals(book_id)
      _ -> :ok
    end
  end

  defp insert_goals(book_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{rows: [[max_pos]]} =
      repo().query!(
        "SELECT COALESCE(MAX(position), -1) FROM training_goals WHERE book_id = $1",
        [book_id]
      )

    goals()
    |> Enum.with_index(max_pos + 1)
    |> Enum.each(fn {{title, date, notes}, pos} ->
      repo().query!(
        "INSERT INTO training_goals
           (book_id, title, target_date, notes, status, position, inserted_at, updated_at)
         SELECT $1, $2, $3, $4, 'active', $5, $6, $6
         WHERE NOT EXISTS (SELECT 1 FROM training_goals WHERE book_id = $1 AND title = $2)",
        [book_id, title, date, notes, pos, now]
      )
    end)
  end
end
