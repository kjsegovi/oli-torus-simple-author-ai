defmodule Oli.GoogleSlides.SlideComponentDetector do
  @moduledoc """
  Heuristically detects interactive components from parsed slide content.
  """

  alias Oli.GoogleSlides.PresentationParser.Slide

  @mcq_min_choices 2
  @mcq_max_choices 6

  @type detect_result :: %{
          component_spec: map() | nil,
          warnings: [map()]
        }

  @spec detect(Slide.t()) :: detect_result()
  def detect(%Slide{} = slide) do
    component_spec =
      detect_mcq(slide) ||
        detect_slider_from_text(slide.notes_text) ||
        detect_slider_from_text(Enum.join(slide.paragraphs, "\n"))

    %{component_spec: component_spec, warnings: []}
  end

  defp detect_mcq(%Slide{list_items: items} = slide) when length(items) >= @mcq_min_choices do
    choices = Enum.take(items, @mcq_max_choices)
    label = mcq_label(slide)

    if label != "" do
      %{
        "component" => "janus-mcq",
        "label" => label,
        "choices" => choices,
        "correct" => 0
      }
    else
      nil
    end
  end

  defp detect_mcq(_), do: nil

  defp mcq_label(%Slide{paragraphs: paragraphs, title: title}) do
    question =
      Enum.find(paragraphs, fn paragraph ->
        String.trim(paragraph) != "" && String.ends_with?(String.trim(paragraph), "?")
      end)

    cond do
      is_binary(question) -> String.trim(question)
      title != "" && String.ends_with?(String.trim(title), "?") -> String.trim(title)
      title != "" -> String.trim(title)
      paragraphs != [] -> String.trim(hd(paragraphs))
      true -> ""
    end
  end

  defp detect_slider_from_text(text) when is_binary(text) do
    text = String.trim(text)

    case Regex.run(~r/(\d+)\s*(?:-|–|to)\s*(\d+)/i, text) do
      [_, min, max] ->
        %{
          "component" => "janus-slider",
          "label" => "Select a value",
          "min" => String.to_integer(min),
          "max" => String.to_integer(max),
          "step" => 1,
          "correct" => String.to_integer(min)
        }

      _ ->
        nil
    end
  end

  defp detect_slider_from_text(_), do: nil
end
