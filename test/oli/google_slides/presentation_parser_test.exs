defmodule Oli.GoogleSlides.PresentationParserTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.PresentationParser

  @fixture Path.expand("../../support/google_slides_import/sample_presentation.json", __DIR__)
           |> File.read!()
           |> Jason.decode!()

  test "parse/2 extracts slide titles and paragraphs" do
    {:ok, slides, _warnings} = PresentationParser.parse(@fixture)

    assert length(slides) == 2
    assert hd(slides).title == "Welcome Slide"
    assert hd(slides).title_from_placeholder == true
    assert hd(slides).paragraphs == ["Intro paragraph text."]
    assert hd(slides).list_items == []
  end
end
