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
      content_blocks: [
        %{type: "paragraph", text: "Which answer is best?"},
        %{type: "list", list_type: "ul", list_id: nil, items: ["One", "Two", "Three"]}
      ],
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

  test "build/3 renders bullet lists as janus-text-flow ul nodes" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "",
      title_from_placeholder: false,
      paragraphs: ["Key points"],
      list_items: ["Alpha", "Beta"],
      content_blocks: [
        %{type: "paragraph", text: "Key points"},
        %{type: "list", list_type: "ul", list_id: "list-1", items: ["Alpha", "Beta"]}
      ],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    {:ok, content, _warnings} = AdaptiveScreenBuilder.build(slide, %{}, llm_fallback: false)

    parts_layout = get_in(content, ["partsLayout"])

    list_part =
      Enum.find(parts_layout, &(get_in(&1, ["custom", "nodes", Access.at(0), "tag"]) == "ul"))

    assert list_part != nil
    items = get_in(list_part, ["custom", "nodes", Access.at(0), "children"])
    assert length(items) == 2

    assert get_in(hd(items), ["children", Access.at(0), "children", Access.at(0), "text"]) ==
             "Alpha"
  end

  test "build/3 renders embedded video as janus-video" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "",
      title_from_placeholder: false,
      paragraphs: [],
      list_items: [],
      content_blocks: [
        %{
          type: "video",
          src: "https://www.youtube.com/watch?v=abc123xyz",
          alt: "Demo",
          height: 280
        }
      ],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    {:ok, content, _warnings} = AdaptiveScreenBuilder.build(slide, %{}, llm_fallback: false)

    video_part = get_in(content, ["partsLayout"]) |> Enum.find(&(&1["type"] == "janus-video"))
    assert get_in(video_part, ["custom", "src"]) == "https://www.youtube.com/watch?v=abc123xyz"
  end

  test "build/3 renders iframe component from bracket tags as janus-capi-iframe" do
    slide = %PresentationParser.Slide{
      index: 1,
      title: "Embed slide",
      title_from_placeholder: false,
      paragraphs: ["[Iframe component: https://example.com/lab]"],
      list_items: [],
      content_blocks: [],
      images: [],
      raw_elements: [],
      notes_text: ""
    }

    {:ok, content, _warnings} = AdaptiveScreenBuilder.build(slide, %{}, llm_fallback: false)

    iframe_part =
      get_in(content, ["partsLayout"]) |> Enum.find(&(&1["type"] == "janus-capi-iframe"))

    assert get_in(iframe_part, ["custom", "src"]) == "https://example.com/lab"
  end
end
