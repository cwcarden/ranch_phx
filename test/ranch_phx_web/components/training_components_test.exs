defmodule RanchPhxWeb.TrainingComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias RanchPhxWeb.TrainingComponents

  describe "answer_blocks/1" do
    test "splits paragraphs, bulleted and numbered lists, and bold" do
      text = """
      From his log, the **left hind** is sticky.
      Keep it short.

      Here's how:
      - Stand at his hip
      - Release on the try

      1. Ask
      2. Release
      """

      assert TrainingComponents.answer_blocks(text) == [
               {:p,
                [
                  [{:t, "From his log, the "}, {:b, "left hind"}, {:t, " is sticky."}],
                  [{:t, "Keep it short."}]
                ]},
               {:p, [[{:t, "Here's how:"}]]},
               {:ul, [[{:t, "Stand at his hip"}], [{:t, "Release on the try"}]]},
               {:ol, [[{:t, "Ask"}], [{:t, "Release"}]]}
             ]
    end

    test "handles empty text" do
      assert TrainingComponents.answer_blocks("") == []
      assert TrainingComponents.answer_blocks(nil) == []
    end
  end

  test "coach_answer renders lists and escapes HTML" do
    html =
      render_component(&TrainingComponents.coach_answer/1,
        text: "Try this:\n- <b>walk</b> him\n- **trot** him"
      )

    assert html =~ "<ul>"
    assert html =~ "<strong>trot</strong>"
    assert html =~ "&lt;b&gt;walk&lt;/b&gt;"
    refute html =~ "<b>walk</b>"
  end
end
