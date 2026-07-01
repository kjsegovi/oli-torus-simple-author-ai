defmodule Oli.GoogleSlides.BracketNotesParserTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.BracketNotesParser

  @experiment_o_matic_notes """
  [Correct Answer] Media framing likely influenced trust in police
  [Correct Feedback] Correct. The experimental group showed lower trust than the control group.
  [Incorrect 1] Try again. This is not supported by the results.
  [Incorrect 2] Try again. Because participants were randomly assigned, pre-existing differences are less likely.
  [Incorrect 4] Try again. Random assignment reduces selection bias, but it does not eliminate all possible sources of bias.
  """

  test "parse/2 builds MCQ from bracket tags and slide list items" do
    slide_context = %{
      title: "Experiment-O-Matic Output",
      paragraphs: [
        "[Multiple choice component]",
        "What's your preliminary interpretation? Given that the experimental group reported lower trust in police than the control group, the results most strongly suggest:"
      ],
      list_items: [
        "The articles had no effect.",
        "Pre-existing differences explain the results.",
        "Media framing likely influenced trust in police.",
        "Random assignment eliminated all bias."
      ]
    }

    assert {:ok, result} = BracketNotesParser.parse(@experiment_o_matic_notes, slide_context)

    assert result.component_spec["component"] == "janus-mcq"
    assert result.component_spec["correct"] == 2
    assert length(result.component_spec["choices"]) == 4
    assert result.adaptivity["maxAttempt"] == 3
    assert result.adaptivity["trapStateScoreScheme"] == true
    assert length(result.adaptivity["commonErrors"]) == 3

    assert Enum.any?(result.adaptivity["commonErrors"], fn error ->
             error["option"] == 1 and String.contains?(error["feedback"], "not supported")
           end)
  end

  test "parse/2 builds two dropdowns from mapping lines" do
    notes = """
    [Correct Answer] Independent variable = type of media framing; Dependent Variable = Level of trust in police
    [Correct Feedback] Correct! Proceed to the project briefing.
    [Blank Feedback] Please match each of the independent and dependent variables.
    [Incorrect IV Feedback] The independent variable is the factor that the researcher manipulates.
    [Incorrect DV Feedback] The dependent variable is the outcome measured after exposure.
    """

    slide_context = %{
      title: "Identify Variables",
      paragraphs: [
        "[Dropdown components]",
        "What are the variables for this project? Match each to its correct variable role.",
        "Independent Variable → Type of media framing",
        "Dependent Variable → Level of trust in police"
      ],
      list_items: []
    }

    assert {:ok, result} = BracketNotesParser.parse(notes, slide_context)

    assert result.component_spec["component"] == "janus-dropdown"
    assert result.component_spec["label"] == "Independent Variable"
    assert length(result.additional_component_specs) == 1
    assert hd(result.additional_component_specs)["label"] == "Dependent Variable"
    assert result.adaptivity["blankFeedback"] =~ "Please match each"
  end

  test "parse/2 reads blank trap feedback from Any not modified tag" do
    notes = """
    [Any not modified Feedback] Make sure to complete all of the settings before submitting the configuration.
    """

    slide_context = %{
      paragraphs: ["[Slider component]"],
      list_items: []
    }

    assert {:ok, result} = BracketNotesParser.parse(notes, slide_context)

    assert result.component_spec == nil
    assert result.adaptivity["blankFeedback"] =~ "complete all of the settings"
  end

  test "parse/2 builds four text sliders for control panel style screens" do
    notes = """
    [Correct Answer Random Assignment] On
    [Correct Answer Group Type] Constructed
    [Correct Answer Pre Test] No
    [Correct Answer Treatment Withholding Allowed] Yes
    [Any not modified Feedback] Make sure to complete all of the settings before submitting the configuration.
    [Incorrect Random Assignment Feedback] Random assignment should be enabled.
    [Incorrect Group Type Feedback] Group type should be constructed.
    """

    slide_context = %{
      title: "Control Panel",
      paragraphs: [
        "[Text slider component: Random Assignment]",
        "[Text slider component: Group Type]",
        "[Text slider component: Pre-Test]",
        "[Text slider component: Treatment Withholding Allowed]",
        "Configure the experiment settings below."
      ],
      list_items: []
    }

    assert {:ok, result} = BracketNotesParser.parse(notes, slide_context)

    specs = [result.component_spec | result.additional_component_specs]
    assert length(specs) == 4
    assert Enum.all?(specs, &(&1["component"] == "janus-text-slider"))

    random = Enum.find(specs, &(&1["label"] == "Random Assignment"))
    assert random["sliderOptionLabels"] == ["Off", "On"]
    assert random["correct"] == 1

    group_type = Enum.find(specs, &(&1["label"] == "Group Type"))
    assert group_type["sliderOptionLabels"] == ["Pre-existing", "Constructed"]
    assert group_type["correct"] == 1

    assert result.adaptivity["requireAllModified"] == true
    assert result.adaptivity["blankFeedback"] =~ "complete all of the settings"

    assert Enum.any?(result.adaptivity["commonErrors"], fn error ->
             error["partKey"] == "random assignment" and
               String.contains?(error["feedback"], "Random assignment")
           end)
  end

  test "parse/2 builds mixed component screen from bracket tags" do
    notes = """
    [Correct Answer] Media framing likely influenced trust in police
    [Correct Answer Hypothesis] students learn better with examples
    [Correct Feedback] Correct!
    """

    slide_context = %{
      title: "Mixed screen",
      paragraphs: [
        "[Multiple choice component]",
        "[Text input component: Hypothesis]",
        "What is your hypothesis?"
      ],
      list_items: ["Option A", "Option B", "Media framing likely influenced trust in police"]
    }

    assert {:ok, result} = BracketNotesParser.parse(notes, slide_context)

    specs = [result.component_spec | result.additional_component_specs]
    assert length(specs) == 2
    assert Enum.at(specs, 0)["component"] == "janus-mcq"
    assert Enum.at(specs, 1)["component"] == "janus-input-text"
    assert Enum.at(specs, 1)["label"] == "Hypothesis"
  end

  test "parse/2 infers text sliders from per-part incorrect feedback tags" do
    notes = """
    [Incorrect Random Assignment Feedback] Enable random assignment.
    [Incorrect Group Type Feedback] Use constructed groups.
    [Any not modified Feedback] Adjust all sliders before continuing.
    """

    slide_context = %{
      paragraphs: ["[Slider component]"],
      list_items: []
    }

    assert {:ok, result} = BracketNotesParser.parse(notes, slide_context)

    specs = [result.component_spec | result.additional_component_specs]
    assert length(specs) == 2
    assert Enum.all?(specs, &(&1["component"] == "janus-text-slider"))
  end

  test "parse/2 builds iframe component from declaration tag and iframe url tag" do
    notes = """
    [Iframe URL] https://example.com/simulation
    [Iframe Scrolling] true
    """

    slide_context = %{
      paragraphs: ["[Iframe component: Lab Simulation]"],
      list_items: []
    }

    assert {:ok, result} = BracketNotesParser.parse(notes, slide_context)

    assert result.component_spec["component"] == "janus-capi-iframe"
    assert result.component_spec["src"] == "https://example.com/simulation"
    assert result.component_spec["allowScrolling"] == true
  end

  test "parse/2 builds iframe component when url is inline in declaration tag" do
    slide_context = %{
      paragraphs: ["[Iframe component: https://example.com/embed]"],
      list_items: []
    }

    assert {:ok, result} = BracketNotesParser.parse("", slide_context)

    assert result.component_spec["component"] == "janus-capi-iframe"
    assert result.component_spec["src"] == "https://example.com/embed"
  end

  test "placeholder_line?/1 detects component placeholders" do
    assert BracketNotesParser.placeholder_line?("[Multiple choice component]")
    refute BracketNotesParser.placeholder_line?("What is the answer?")
  end
end
