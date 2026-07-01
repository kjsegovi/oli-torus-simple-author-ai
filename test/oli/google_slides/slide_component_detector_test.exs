defmodule Oli.GoogleSlides.SlideComponentDetectorTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.{PresentationParser, SlideComponentDetector}

  test "detect/1 builds MCQ from question paragraph and list items" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "Quiz",
      title_from_placeholder: false,
      paragraphs: ["Which option is correct?"],
      list_items: ["Alpha", "Beta", "Gamma"],
      content_blocks: [],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    %{component_spec: spec} = SlideComponentDetector.detect(slide)

    assert spec["component"] == "janus-mcq"
    assert spec["choices"] == ["Alpha", "Beta", "Gamma"]
    assert spec["label"] == "Which option is correct?"
  end

  test "detect/1 builds slider from numeric range in notes" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "",
      title_from_placeholder: false,
      paragraphs: ["Adjust the value"],
      list_items: [],
      content_blocks: [],
      images: [],
      raw_elements: [],
      notes_text: "Use a slider from 0 to 100"
    }

    %{component_spec: spec} = SlideComponentDetector.detect(slide)

    assert spec["component"] == "janus-slider"
    assert spec["min"] == 0
    assert spec["max"] == 100
  end
end
