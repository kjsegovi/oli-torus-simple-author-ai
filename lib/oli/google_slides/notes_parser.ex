defmodule Oli.GoogleSlides.NotesParser do
  @moduledoc """
  Parses speaker notes into component specs and adaptivity directives.

  Uses structured fenced YAML blocks first, then GenAI when configured.
  """

  alias Oli.GoogleSlides.{BracketNotesParser, GenAI, Warnings}

  @structured_block ~r/```(?:torus|yaml)\s*\n([\s\S]*?)```/i

  @type parse_result :: %{
          component_spec: map() | nil,
          adaptivity: map() | nil,
          warnings: [map()]
        }

  @spec parse(String.t(), map(), keyword()) :: parse_result()
  def parse(notes_text, slide_context \\ %{}, opts \\ []) do
    warnings = []
    slide_index = Map.get(slide_context, :slide_index, 0)
    llm_fallback = Keyword.get(opts, :llm_fallback, GenAI.configured?())

    case extract_structured_block(notes_text) do
      {:ok, yaml} ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, spec} when is_map(spec) ->
            %{
              component_spec: component_spec(spec),
              additional_component_specs: [],
              adaptivity: adaptivity_spec(spec),
              warnings: warnings
            }

          {:error, reason} ->
            %{
              component_spec: nil,
              additional_component_specs: [],
              adaptivity: nil,
              warnings: [
                Warnings.build(:notes_parse_error, %{
                  slide_index: slide_index,
                  reason: inspect(reason)
                })
              ]
            }
        end

      :not_found ->
        metadata_text = metadata_text(notes_text, slide_context)

        case BracketNotesParser.parse(metadata_text, slide_context) do
          {:ok, bracket_result} ->
            %{
              component_spec: bracket_result.component_spec,
              additional_component_specs:
                Map.get(bracket_result, :additional_component_specs, []),
              adaptivity: bracket_result.adaptivity,
              warnings: bracket_result.warnings
            }

          :not_found ->
            if llm_fallback do
              llm_fallback(notes_text, slide_context, warnings, slide_index)
            else
              %{
                component_spec: nil,
                additional_component_specs: [],
                adaptivity: nil,
                warnings: warnings
              }
            end
        end
    end
  end

  defp metadata_text(notes_text, slide_context) do
    body = Map.get(slide_context, :paragraphs, []) |> Enum.join("\n")

    [notes_text, body]
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join("\n\n")
  end

  defp extract_structured_block(text) when is_binary(text) do
    case Regex.run(@structured_block, text) do
      [_, yaml] -> {:ok, String.trim(yaml)}
      _ -> :not_found
    end
  end

  defp extract_structured_block(_), do: :not_found

  defp component_spec(%{"component" => component} = spec) when is_binary(component) do
    spec
    |> Map.put("component", normalize_component(component))
    |> Map.drop([
      "onCorrect",
      "onIncorrect",
      "score",
      "maxAttempt",
      "trapStateScoreScheme",
      "commonErrors"
    ])
  end

  defp component_spec(_), do: nil

  defp adaptivity_spec(spec) when is_map(spec) do
    %{
      "score" => Map.get(spec, "score", 0),
      "correctFeedback" => Map.get(spec, "correctFeedback"),
      "incorrectFeedback" => Map.get(spec, "incorrectFeedback"),
      "blankFeedback" => Map.get(spec, "blankFeedback"),
      "onCorrect" => Map.get(spec, "onCorrect", "navigate next"),
      "onIncorrect" => Map.get(spec, "onIncorrect", "show feedback"),
      "maxAttempt" => Map.get(spec, "maxAttempt"),
      "trapStateScoreScheme" => Map.get(spec, "trapStateScoreScheme", false),
      "commonErrors" => Map.get(spec, "commonErrors", [])
    }
  end

  defp normalize_component("janus-slider"), do: "janus-slider"
  defp normalize_component("slider"), do: "janus-slider"
  defp normalize_component("janus-mcq"), do: "janus-mcq"
  defp normalize_component("mcq"), do: "janus-mcq"
  defp normalize_component("multiple_choice"), do: "janus-mcq"
  defp normalize_component("janus-capi-iframe"), do: "janus-capi-iframe"
  defp normalize_component("iframe"), do: "janus-capi-iframe"
  defp normalize_component("capi-iframe"), do: "janus-capi-iframe"
  defp normalize_component(other), do: other

  defp llm_fallback(notes_text, slide_context, warnings, slide_index) do
    case Oli.GoogleSlides.NotesParser.LlmFallback.interpret(notes_text, slide_context) do
      {:ok, result} ->
        Map.put(result, :warnings, warnings)
        |> Map.put(:additional_component_specs, Map.get(result, :additional_component_specs, []))

      {:error, _reason} ->
        %{
          component_spec: nil,
          additional_component_specs: [],
          adaptivity: nil,
          warnings:
            warnings ++
              [
                Warnings.build(:notes_llm_fallback_failed, %{slide_index: slide_index})
              ]
        }
    end
  end
end
