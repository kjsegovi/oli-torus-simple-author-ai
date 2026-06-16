defmodule Oli.GoogleSlides.AdaptiveRulesBuilder do
  @moduledoc """
  Builds expert-mode adaptive rules from parsed note directives.
  """

  alias Oli.GoogleSlides.Adaptive.PartBuilders
  alias Oli.GoogleSlides.Util

  @spec build_rules(map() | nil, map() | nil, [map()]) :: [map()]
  def build_rules(adaptivity, component_part, parts_layout) do
    scorable_part = find_scorable_part(component_part, parts_layout)

    case {adaptivity, scorable_part} do
      {nil, _} ->
        default_rules()

      {_, nil} ->
        default_rules()

      {adaptivity, part} ->
        rule_id = Util.new_rule_id()
        score = Map.get(adaptivity, "score", 0)

        [
          correct_rule(rule_id, part, adaptivity, score),
          incorrect_rule(rule_id, part, adaptivity)
        ]
    end
  end

  defp find_scorable_part(%{"id" => id}, parts_layout) do
    Enum.find(parts_layout, &(&1["id"] == id))
  end

  defp find_scorable_part(nil, parts_layout) do
    Enum.find(parts_layout, &(&1["type"] in ["janus-mcq", "janus-slider"]))
  end

  defp default_rules do
    rule_id = Util.new_rule_id()

    [
      %{
        "id" => "#{rule_id}.correct",
        "name" => "correct",
        "disabled" => false,
        "additionalScore" => 0.0,
        "forceProgress" => false,
        "default" => true,
        "correct" => true,
        "conditions" => %{"all" => []},
        "event" => %{
          "type" => "#{rule_id}.correct",
          "params" => %{
            "actions" => [
              %{"type" => "navigation", "params" => %{"target" => "next"}}
            ]
          }
        }
      },
      %{
        "id" => "#{rule_id}.defaultWrong",
        "name" => "defaultWrong",
        "disabled" => false,
        "additionalScore" => 0.0,
        "forceProgress" => false,
        "default" => true,
        "correct" => false,
        "conditions" => %{"all" => []},
        "event" => %{
          "type" => "#{rule_id}.defaultWrong",
          "params" => %{
            "actions" => [feedback_action("Incorrect, please try again.")]
          }
        }
      }
    ]
  end

  defp correct_rule(rule_id, part, adaptivity, score) do
    feedback = Map.get(adaptivity, "correctFeedback", "Correct!")
    on_correct = Map.get(adaptivity, "onCorrect", "navigate next")

    actions =
      case on_correct do
        "navigate next" ->
          [
            %{"type" => "navigation", "params" => %{"target" => "next"}},
            feedback_action(feedback)
          ]

        _ ->
          [feedback_action(feedback)]
      end

    %{
      "id" => "#{rule_id}.correct",
      "name" => "correct",
      "disabled" => false,
      "additionalScore" => score * 1.0,
      "forceProgress" => false,
      "default" => false,
      "correct" => true,
      "conditions" => %{"all" => [condition_for_part(part, true)]},
      "event" => %{
        "type" => "#{rule_id}.correct",
        "params" => %{"actions" => actions}
      }
    }
  end

  defp incorrect_rule(rule_id, part, adaptivity) do
    feedback = Map.get(adaptivity, "incorrectFeedback", "Incorrect, please try again.")

    %{
      "id" => "#{rule_id}.incorrect",
      "name" => "incorrect",
      "disabled" => false,
      "additionalScore" => 0.0,
      "forceProgress" => false,
      "default" => false,
      "correct" => false,
      "conditions" => %{"all" => [condition_for_part(part, false)]},
      "event" => %{
        "type" => "#{rule_id}.incorrect",
        "params" => %{
          "actions" => [feedback_action(feedback)]
        }
      }
    }
  end

  defp condition_for_part(%{"id" => part_id, "type" => "janus-mcq"}, true) do
    %{
      "fact" => "stage.#{part_id}.isCorrect",
      "operator" => "equal",
      "value" => true
    }
  end

  defp condition_for_part(%{"id" => part_id, "type" => "janus-mcq"}, false) do
    %{
      "fact" => "stage.#{part_id}.isCorrect",
      "operator" => "equal",
      "value" => false
    }
  end

  defp condition_for_part(%{"id" => part_id, "type" => "janus-slider"}, true) do
    %{
      "fact" => "stage.#{part_id}.isCorrect",
      "operator" => "equal",
      "value" => true
    }
  end

  defp condition_for_part(%{"id" => part_id, "type" => "janus-slider"}, false) do
    %{
      "fact" => "stage.#{part_id}.isCorrect",
      "operator" => "equal",
      "value" => false
    }
  end

  defp feedback_action(message) do
    feedback_part = PartBuilders.feedback_text_part(message)

    %{
      "type" => "feedback",
      "params" => %{
        "id" => "a_f_#{Util.new_id("fb")}",
        "feedback" => %{
          "custom" => %{
            "applyBtnFlag" => false,
            "applyBtnLabel" => "Show Solution",
            "mainBtnLabel" => "Next",
            "panelTitleColor" => 16_777_215,
            "panelHeaderColor" => 10_027_008,
            "lockCanvasSize" => true,
            "width" => 350.0,
            "height" => 100.0,
            "palette" => %{
              "fillColor" => 1.6777215e7,
              "fillAlpha" => 0.0,
              "lineColor" => 1.6777215e7,
              "lineAlpha" => 0.0,
              "lineThickness" => 0.1,
              "lineStyle" => 0.0
            },
            "rules" => [],
            "facts" => []
          },
          "partsLayout" => [feedback_part]
        }
      }
    }
  end
end
