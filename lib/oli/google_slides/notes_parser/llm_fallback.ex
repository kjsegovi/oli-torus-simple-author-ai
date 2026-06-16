defmodule Oli.GoogleSlides.NotesParser.LlmFallback do
  @moduledoc """
  LLM interpretation of freeform speaker notes for Google Slides import.
  """

  require Logger

  alias Oli.GoogleSlides.GenAI

  @spec interpret(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def interpret(notes_text, slide_context) do
    notes_text = String.trim(notes_text || "")

    if notes_text == "" do
      {:ok, %{component_spec: nil, adaptivity: nil}}
    else
      with {:ok, content} <- call_model(notes_text, slide_context) do
        parse_json_response(content)
      end
    end
  end

  defp call_model(notes_text, slide_context) do
    slide_title = Map.get(slide_context, :title, "")
    slide_body = Map.get(slide_context, :paragraphs, []) |> Enum.join("\n")
    list_items = Map.get(slide_context, :list_items, []) |> Enum.join(", ")

    prompt = """
    Interpret the speaker notes for an adaptive learning slide and return JSON only.

    Slide title: #{slide_title}
    Slide body: #{slide_body}
    Slide list items: #{list_items}

    Speaker notes:
    #{notes_text}

    Return JSON with keys:
    - component (optional): one of janus-slider, janus-mcq, or null
    - label, min, max, step, correct, choices (for mcq array of strings)
    - correctFeedback, incorrectFeedback, score
    - onCorrect (navigate next or show feedback)
    - onIncorrect (navigate next or show feedback)
    - maxAttempt (integer, default 3 for scorable slides)
    - trapStateScoreScheme (boolean)
    - commonErrors (optional array of {option: integer, feedback: string} for MCQ)
    """

    GenAI.complete(prompt)
  end

  defp parse_json_response(content) do
    json = GenAI.strip_code_fence(content)

    case Jason.decode(json) do
      {:ok, spec} when is_map(spec) ->
        component = Map.get(spec, "component")

        {:ok,
         %{
           component_spec: if(is_binary(component), do: spec, else: nil),
           additional_component_specs: [],
           adaptivity: %{
             "score" => Map.get(spec, "score", 0),
             "correctFeedback" => Map.get(spec, "correctFeedback"),
             "incorrectFeedback" => Map.get(spec, "incorrectFeedback"),
             "onCorrect" => Map.get(spec, "onCorrect", "navigate next"),
             "onIncorrect" => Map.get(spec, "onIncorrect", "show feedback"),
             "maxAttempt" => Map.get(spec, "maxAttempt"),
             "trapStateScoreScheme" => Map.get(spec, "trapStateScoreScheme", false),
             "commonErrors" => Map.get(spec, "commonErrors", [])
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
