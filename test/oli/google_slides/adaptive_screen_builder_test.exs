defmodule Oli.GoogleSlides.AdaptiveScreenBuilderTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.AdaptiveScreenBuilder
  alias Oli.GoogleSlides.PresentationParser

  @fixture Path.expand("../../support/google_slides_import/sample_presentation.json", __DIR__)
           |> File.read!()
           |> Jason.decode!()

  test "build/3 assembles oli_adaptive content" do
    {:ok, [slide | _], _} = PresentationParser.parse(@fixture)

    {:ok, content, _warnings} = AdaptiveScreenBuilder.build(slide, %{})

    assert get_in(content, ["authoring", "parts"]) != []
    assert get_in(content, ["partsLayout"]) != []
    assert get_in(content, ["authoring", "rules"]) != []
    assert get_in(content, ["custom", "palette", "useHtmlProps"]) == true
    assert get_in(content, ["custom", "showCheckBtn"]) == true
  end

  test "build/3 sets scorable part outOf and trap defaults for MCQ from slide lists" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "Question slide",
      title_from_placeholder: false,
      paragraphs: ["Which answer is best?"],
      list_items: ["One", "Two", "Three"],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    {:ok, content, _warnings} = AdaptiveScreenBuilder.build(slide, %{}, llm_fallback: false)

    parts = get_in(content, ["authoring", "parts"])
    mcq_part = Enum.find(parts, &(&1["type"] == "janus-mcq"))

    assert mcq_part["outOf"] == 1
    assert mcq_part["gradingApproach"] == "automatic"
    assert get_in(content, ["custom", "maxAttempt"]) == 3
    assert get_in(content, ["custom", "showCheckBtn"]) == true

    rule_names = content |> get_in(["authoring", "rules"]) |> Enum.map(& &1["name"])
    assert "correct" in rule_names
    assert "blank" in rule_names
    assert "incorrect-max-attempt" in rule_names
  end
end
