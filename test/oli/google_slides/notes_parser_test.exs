defmodule Oli.GoogleSlides.NotesParserTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.NotesParser

  test "parse/3 reads structured yaml block with trap adaptivity fields" do
    notes = """
    Some freeform notes

    ```torus
    component: janus-slider
    label: What is the answer?
    min: 0
    max: 100
    step: 1
    correct: 42
    correctFeedback: Amazing job
    incorrectFeedback: Try again
    score: 5
    maxAttempt: 3
    trapStateScoreScheme: true
    onIncorrect: show feedback
    commonErrors:
      - option: 2
        feedback: Common mistake
    ```
    """

    result = NotesParser.parse(notes, %{slide_index: 1}, llm_fallback: false)

    assert result.component_spec["component"] == "janus-slider"
    assert result.component_spec["correct"] == 42
    assert result.adaptivity["score"] == 5
    assert result.adaptivity["maxAttempt"] == 3
    assert result.adaptivity["trapStateScoreScheme"] == true
    assert result.adaptivity["onIncorrect"] == "show feedback"
    assert length(result.adaptivity["commonErrors"]) == 1
  end

  test "parse/3 uses bracket tags from speaker notes before heuristics" do
    notes = """
    [Correct Answer] Media framing likely influenced trust in police
    [Correct Feedback] Correct. Great job.
    [Incorrect 1] Try again for option one.
    """

    result =
      NotesParser.parse(
        notes,
        %{
          slide_index: 1,
          title: "Experiment-O-Matic Output",
          paragraphs: [
            "[Multiple choice component]",
            "What do the results suggest?"
          ],
          list_items: [
            "The articles had no effect.",
            "Pre-existing differences explain the results.",
            "Media framing likely influenced trust in police.",
            "Random assignment eliminated all bias."
          ]
        },
        llm_fallback: false
      )

    assert result.component_spec["component"] == "janus-mcq"
    assert result.component_spec["correct"] == 2
    assert length(result.adaptivity["commonErrors"]) == 1
  end

  test "parse/3 returns empty specs when notes are blank" do
    result = NotesParser.parse("", %{slide_index: 1}, llm_fallback: false)
    assert result.component_spec == nil
    assert result.adaptivity == nil
  end
end
