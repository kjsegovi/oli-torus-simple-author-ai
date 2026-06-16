defmodule Oli.GoogleSlides.ScreenTitleGeneratorTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.{PresentationParser, ScreenTitleGenerator}

  test "heuristic_title/1 truncates long slide text" do
    slide = %PresentationParser.Slide{
      index: 2,
      title:
        "This is an extremely long slide title that should never be used verbatim as a screen name in the curriculum view",
      title_from_placeholder: false,
      paragraphs: [],
      list_items: [],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    title = ScreenTitleGenerator.heuristic_title(slide)

    assert String.length(title) <= 51
    assert String.ends_with?(title, "…")
  end

  test "heuristic_title/1 uses short placeholder titles as-is" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "Ethics Overview",
      title_from_placeholder: true,
      paragraphs: [],
      list_items: [],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    assert ScreenTitleGenerator.heuristic_title(slide) == "Ethics Overview"
  end

  test "generate_all/1 returns heuristic titles when GenAI is not configured" do
    slides = [
      %PresentationParser.Slide{
        index: 1,
        title: "Short title",
        title_from_placeholder: true,
        paragraphs: [],
        list_items: [],
        images: [],
        raw_elements: [],
        notes_text: ""
      }
    ]

    {titles, warnings} = ScreenTitleGenerator.generate_all(slides)

    assert titles[1] == "Short title"
    assert warnings == []
  end
end
