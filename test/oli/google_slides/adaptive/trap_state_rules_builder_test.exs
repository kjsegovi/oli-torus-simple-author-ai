defmodule Oli.GoogleSlides.Adaptive.TrapStateRulesBuilderTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.Adaptive.{PartBuilders, TrapStateRulesBuilder}

  test "build_rules/3 creates 3-try workflow for MCQ screens" do
    spec = %{
      "component" => "janus-mcq",
      "label" => "Pick one",
      "choices" => ["A", "B"],
      "correct" => 0,
      "correctFeedback" => "Nice",
      "incorrectFeedback" => "Nope"
    }

    part = PartBuilders.mcq_part(spec, y: 100)

    adaptivity = %{
      "score" => 5,
      "maxAttempt" => 3,
      "trapStateScoreScheme" => true,
      "onCorrect" => "navigate next",
      "onIncorrect" => "show feedback",
      "commonErrors" => [%{"option" => 2, "feedback" => "Common mistake"}]
    }

    rules = TrapStateRulesBuilder.build_rules(adaptivity, part, [part])

    rule_names = Enum.map(rules, & &1["name"])

    assert "correct" in rule_names
    assert "blank" in rule_names
    assert "incorrect-max-attempt" in rule_names
    assert "default-incorrect" in rule_names
    assert Enum.any?(rule_names, &String.starts_with?(&1, "common-error-"))

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    assert get_in(correct_rule, ["conditions", "all", Access.at(0), "fact"]) =~ ".selectedChoice"

    max_attempt_rule = Enum.find(rules, &(&1["name"] == "incorrect-max-attempt"))
    assert get_in(max_attempt_rule, ["event", "params", "actions"]) != []
  end

  test "build_rules/3 never adds component disable actions" do
    spec = %{
      "component" => "janus-mcq",
      "label" => "Pick one",
      "choices" => ["A", "B"],
      "correct" => 0
    }

    part = PartBuilders.mcq_part(spec, y: 100)

    for adaptivity <- [
          %{"maxAttempt" => 3, "onCorrect" => "navigate next", "onIncorrect" => "navigate next"},
          %{"maxAttempt" => 3, "onCorrect" => "show feedback", "onIncorrect" => "show feedback"}
        ] do
      rules = TrapStateRulesBuilder.build_rules(adaptivity, part, [part])

      enabled_targets =
        rules
        |> Enum.flat_map(&(get_in(&1, ["event", "params", "actions"]) || []))
        |> Enum.filter(&(&1["type"] == "mutateState"))
        |> Enum.map(&get_in(&1, ["params", "target"]))
        |> Enum.filter(&is_binary/1)
        |> Enum.filter(&String.ends_with?(&1, ".enabled"))

      assert enabled_targets == []
    end
  end

  @golden Path.expand("../../../support/google_slides_import/trap_workflow_golden.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()

  test "build_rules/3 matches trap workflow golden fixture shape" do
    spec = %{
      "component" => "janus-mcq",
      "label" => "Pick one",
      "choices" => ["A", "B"],
      "correct" => 0
    }

    part = PartBuilders.mcq_part(spec, y: 100)
    part_id = part["id"]

    adaptivity = %{"maxAttempt" => @golden["maxAttempt"], "score" => 1}

    rules = TrapStateRulesBuilder.build_rules(adaptivity, part, [part])
    rule_names = Enum.map(rules, & &1["name"])

    for required <- @golden["requiredRuleNames"] do
      assert required in rule_names
    end

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    fact = get_in(correct_rule, ["conditions", "all", Access.at(0), "fact"])
    assert fact == String.replace(hd(@golden["correctRuleFacts"]), "{partId}", part_id)

    max_rule = Enum.find(rules, &(&1["name"] == "incorrect-max-attempt"))
    attempt_condition = get_in(max_rule, ["conditions", "all", Access.at(0)])

    assert attempt_condition["fact"] == @golden["maxAttemptCondition"]["fact"]
    assert attempt_condition["operator"] == @golden["maxAttemptCondition"]["operator"]
  end

  test "build_rules/3 creates multi-part trap workflow for text sliders" do
    specs = [
      %{
        "component" => "janus-text-slider",
        "label" => "Random Assignment",
        "sliderOptionLabels" => ["Off", "On"],
        "correct" => 1
      },
      %{
        "component" => "janus-text-slider",
        "label" => "Group Type",
        "sliderOptionLabels" => ["Pre-existing", "Constructed"],
        "correct" => 1
      }
    ]

    parts = Enum.map(specs, &PartBuilders.text_slider_part(&1, y: 100))

    adaptivity = %{
      "maxAttempt" => 3,
      "requireAllModified" => true,
      "commonErrors" => [
        %{"partKey" => "random assignment", "feedback" => "Enable random assignment."}
      ]
    }

    rules = TrapStateRulesBuilder.build_rules(adaptivity, hd(parts), parts, parts)

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    assert length(get_in(correct_rule, ["conditions", "all"])) == 2

    blank_rule = Enum.find(rules, &(&1["name"] == "blank"))
    assert Map.has_key?(blank_rule["conditions"], "any")

    assert Enum.any?(rules, &String.starts_with?(&1["name"], "common-error-"))
  end

  test "build_rules/3 falls back to simple rules when no scorable part" do
    rules = TrapStateRulesBuilder.build_rules(%{"maxAttempt" => 3}, nil, [])

    assert length(rules) == 2
    assert Enum.all?(rules, &Map.has_key?(&1, "default"))
  end

  test "build_rules/3 uses selectedIndex conditions for dropdown trap workflow" do
    specs = [
      %{
        "component" => "janus-dropdown",
        "label" => "Independent Variable",
        "optionLabels" => ["Type of media framing", "Level of trust in police"],
        "correct" => 0
      },
      %{
        "component" => "janus-dropdown",
        "label" => "Dependent Variable",
        "optionLabels" => ["Type of media framing", "Level of trust in police"],
        "correct" => 1
      }
    ]

    parts = Enum.map(specs, &PartBuilders.dropdown_part(&1, y: 100))

    adaptivity = %{
      "maxAttempt" => 3,
      "commonErrors" => [
        %{"partKey" => "IV", "feedback" => "The independent variable is manipulated."},
        %{"partKey" => "DV", "feedback" => "The dependent variable is measured."}
      ]
    }

    rules = TrapStateRulesBuilder.build_rules(adaptivity, hd(parts), parts, parts)

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    facts = get_in(correct_rule, ["conditions", "all"]) |> Enum.map(& &1["fact"])

    assert Enum.all?(facts, &String.contains?(&1, ".selectedIndex"))
    refute Enum.any?(facts, &String.contains?(&1, ".isCorrect"))

    iv_part = Enum.find(parts, &(&1["custom"]["label"] == "Independent Variable"))
    dv_part = Enum.find(parts, &(&1["custom"]["label"] == "Dependent Variable"))

    assert Enum.any?(get_in(correct_rule, ["conditions", "all"]), fn condition ->
             condition["fact"] == "stage.#{iv_part["id"]}.selectedIndex" and
               condition["value"] == "1"
           end)

    assert Enum.any?(get_in(correct_rule, ["conditions", "all"]), fn condition ->
             condition["fact"] == "stage.#{dv_part["id"]}.selectedIndex" and
               condition["value"] == "2"
           end)

    iv_error = Enum.find(rules, &(&1["name"] == "common-error-1"))
    iv_fact = get_in(iv_error, ["conditions", "all", Access.at(1), "fact"])
    assert iv_fact == "stage.#{iv_part["id"]}.selectedIndex"

    max_attempt_rule = Enum.find(rules, &(&1["name"] == "incorrect-max-attempt"))

    set_index_actions =
      max_attempt_rule
      |> get_in(["event", "params", "actions"])
      |> Enum.filter(fn action ->
        target = get_in(action, ["params", "target"])
        is_binary(target) and String.contains?(target, ".selectedIndex")
      end)

    assert length(set_index_actions) == 2
  end

  test "build_rules/3 uses text input schema facts for correct, blank, and max-attempt rules" do
    spec = %{
      "component" => "janus-input-text",
      "label" => "Hypothesis",
      "correctAnswer" => %{
        "minimumLength" => 3,
        "mustContain" => "because",
        "mustNotContain" => "maybe"
      }
    }

    part = PartBuilders.input_text_part(spec, y: 100)
    part_id = part["id"]

    rules =
      TrapStateRulesBuilder.build_rules(
        %{"maxAttempt" => 3, "onCorrect" => "show feedback"},
        part,
        [part]
      )

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    correct_facts = get_in(correct_rule, ["conditions", "all"]) |> Enum.map(& &1["fact"])

    assert "stage.#{part_id}.text" in correct_facts
    assert "stage.#{part_id}.textLength" in correct_facts

    assert Enum.any?(get_in(correct_rule, ["conditions", "all"]), fn condition ->
             condition["operator"] == "notContains" and condition["value"] == "maybe"
           end)

    blank_rule = Enum.find(rules, &(&1["name"] == "blank"))
    blank_condition = get_in(blank_rule, ["conditions", "all", Access.at(0)])

    assert blank_condition["fact"] == "stage.#{part_id}.textLength"
    assert blank_condition["operator"] == "lessThan"
    assert blank_condition["value"] == "3"

    max_attempt_rule = Enum.find(rules, &(&1["name"] == "incorrect-max-attempt"))
    max_conditions = get_in(max_attempt_rule, ["conditions", "all"])

    assert length(max_conditions) == 1
    assert hd(max_conditions)["fact"] == "session.attemptNumber"
  end

  test "build_rules/3 uses isNaN blank and numeric value conditions for input number" do
    spec = %{
      "component" => "janus-input-number",
      "label" => "Count",
      "correct" => 7
    }

    part = PartBuilders.input_number_part(spec, y: 100)
    part_id = part["id"]

    rules = TrapStateRulesBuilder.build_rules(%{"maxAttempt" => 3}, part, [part])

    blank_rule = Enum.find(rules, &(&1["name"] == "blank"))
    blank_condition = get_in(blank_rule, ["conditions", "all", Access.at(0)])

    assert blank_condition["fact"] == "stage.#{part_id}.value"
    assert blank_condition["operator"] == "isNaN"

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    value_condition = get_in(correct_rule, ["conditions", "all", Access.at(0)])

    assert value_condition["fact"] == "stage.#{part_id}.value"
    assert value_condition["operator"] == "equal"
    assert value_condition["value"] == "7"
  end

  test "build_rules/3 supports numeric range answers for sliders" do
    part = %{
      "id" => "slider_range_test",
      "type" => "janus-slider",
      "custom" => %{
        "answer" => %{"range" => true, "correctMin" => 2, "correctMax" => 4}
      }
    }

    rules = TrapStateRulesBuilder.build_rules(%{"maxAttempt" => 3}, part, [part])

    correct_rule = Enum.find(rules, &(&1["name"] == "correct"))
    condition = get_in(correct_rule, ["conditions", "all", Access.at(0)])

    assert condition["operator"] == "inRange"
    assert condition["value"] == "[2,4]"

    max_attempt_rule = Enum.find(rules, &(&1["name"] == "incorrect-max-attempt"))

    set_value_action =
      max_attempt_rule
      |> get_in(["event", "params", "actions"])
      |> Enum.find(&(get_in(&1, ["params", "target"]) == "stage.slider_range_test.value"))

    assert get_in(set_value_action, ["params", "value"]) == "2"
  end
end
