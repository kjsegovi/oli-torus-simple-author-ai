defmodule Oli.GoogleSlides.ScreenTitleGenerator do
  @moduledoc """
  Generates concise screen titles for imported slides using heuristics and optional GenAI.
  """

  alias Oli.GoogleSlides.{GenAI, PresentationParser.Slide, Warnings}

  @max_title_length 60
  @truncate_length 50

  @spec generate_all([Slide.t()]) :: {map(), [map()]}
  def generate_all(slides) when is_list(slides) do
    heuristic_titles =
      slides
      |> Enum.map(fn slide -> {slide.index, heuristic_title(slide)} end)
      |> Map.new()

    case GenAI.configured?() do
      true ->
        case generate_with_genai(slides) do
          {:ok, ai_titles} ->
            titles =
              Enum.reduce(slides, %{}, fn slide, acc ->
                title =
                  Map.get(ai_titles, slide.index) ||
                    Map.get(heuristic_titles, slide.index) ||
                    fallback_title(slide)

                Map.put(acc, slide.index, title)
              end)

            {titles, []}

          {:error, _reason} ->
            warnings =
              Enum.map(slides, fn slide ->
                Warnings.build(:screen_title_generation_failed, %{slide_index: slide.index})
              end)

            {heuristic_titles, warnings}
        end

      false ->
        {heuristic_titles, []}
    end
  end

  @spec heuristic_title(Slide.t()) :: String.t()
  def heuristic_title(%Slide{} = slide) do
    cond do
      slide.title_from_placeholder && String.length(slide.title) <= @max_title_length ->
        String.trim(slide.title)

      slide.title != "" && String.length(slide.title) <= @max_title_length ->
        String.trim(slide.title)

      first_text = first_non_empty([slide.title | slide.paragraphs]) ->
        truncate_title(first_text)

      true ->
        fallback_title(slide)
    end
  end

  defp generate_with_genai(slides) do
    payload =
      slides
      |> Enum.map(fn slide ->
        %{
          index: slide.index,
          title: slide.title,
          paragraphs: slide.paragraphs,
          notes: String.slice(slide.notes_text || "", 0, 500)
        }
      end)
      |> Jason.encode!()

    prompt = """
    Generate concise screen titles for an adaptive learning lesson imported from Google Slides.

    For each slide, return a short pedagogical screen name (max #{@max_title_length} characters).
    Do not copy full slide body text. Use a label-style name, not a sentence. No trailing punctuation.

    Slides JSON:
    #{payload}

    Return JSON only: an array of objects with keys "index" (integer) and "screenTitle" (string).
    """

    with {:ok, content} <- GenAI.complete(prompt),
         {:ok, decoded} <- Jason.decode(GenAI.strip_code_fence(content)) do
      titles =
        decoded
        |> List.wrap()
        |> Enum.reduce(%{}, fn
          %{"index" => index, "screenTitle" => title}, acc when is_binary(title) ->
            Map.put(acc, index, sanitize_title(title))

          _, acc ->
            acc
        end)

      {:ok, titles}
    end
  end

  defp sanitize_title(title) do
    title
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> truncate_title()
  end

  defp truncate_title(text) do
    text = String.trim(text)

    if String.length(text) <= @truncate_length do
      text
    else
      text
      |> String.slice(0, @truncate_length)
      |> String.trim()
      |> Kernel.<>("…")
    end
  end

  defp fallback_title(%{index: index}), do: "Slide #{index}"

  defp first_non_empty(texts) do
    Enum.find_value(texts, fn
      text when is_binary(text) ->
        trimmed = String.trim(text)
        if trimmed != "", do: trimmed

      _ ->
        nil
    end)
  end
end
