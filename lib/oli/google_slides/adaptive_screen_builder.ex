defmodule Oli.GoogleSlides.AdaptiveScreenBuilder do
  @moduledoc """
  Assembles one `oli_adaptive` activity content map from a parsed slide.
  """

  alias Oli.GoogleSlides.Adaptive.PartBuilders
  alias Oli.GoogleSlides.Adaptive.TrapStateRulesBuilder
  alias Oli.GoogleSlides.BracketNotesParser
  alias Oli.GoogleSlides.NotesParser
  alias Oli.GoogleSlides.PresentationParser.Slide
  alias Oli.GoogleSlides.SlideComponentDetector
  alias Oli.GoogleSlides.Warnings

  @default_width 1000
  @default_height 540

  @default_screen_custom %{
    "applyBtnFlag" => false,
    "applyBtnLabel" => "",
    "checkButtonLabel" => "Next",
    "combineFeedback" => false,
    "customCssClass" => "",
    "facts" => [],
    "lockCanvasSize" => false,
    "mainBtnLabel" => "",
    "maxAttempt" => 0,
    "maxScore" => 0,
    "negativeScoreAllowed" => false,
    "palette" => %{
      "backgroundColor" => "rgba(255,255,255,0)",
      "borderColor" => "rgba(255,255,255,0)",
      "borderRadius" => "",
      "borderStyle" => "solid",
      "borderWidth" => "1px",
      "useHtmlProps" => true
    },
    "panelHeaderColor" => 0,
    "panelTitleColor" => 0,
    "showCheckBtn" => true,
    "trapStateScoreScheme" => false,
    "width" => @default_width,
    "height" => @default_height,
    "x" => 0,
    "y" => 0,
    "z" => 0
  }

  @spec build(Slide.t(), map(), keyword()) :: {:ok, map(), [map()]}
  def build(%Slide{} = slide, media_urls, opts \\ []) do
    llm_fallback = Keyword.get(opts, :llm_fallback, true)
    warnings = []

    notes_result =
      NotesParser.parse(
        slide.notes_text,
        %{
          slide_index: slide.index,
          title: slide.title,
          paragraphs: slide.paragraphs,
          list_items: slide.list_items
        },
        llm_fallback: llm_fallback
      )

    warnings = warnings ++ notes_result.warnings

    component_result = SlideComponentDetector.detect(slide)
    warnings = warnings ++ component_result.warnings

    component_specs =
      [notes_result.component_spec | notes_result.additional_component_specs || []]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] ->
          case component_result.component_spec do
            nil -> []
            spec -> [spec]
          end

        specs ->
          specs
      end

    {parts_layout, component_parts, part_warnings} =
      build_parts_layout(slide, media_urls, component_specs)

    warnings = warnings ++ part_warnings

    authoring_parts = Enum.map(parts_layout, &PartBuilders.authoring_part/1)
    primary_component_part = List.first(component_parts)

    rules =
      TrapStateRulesBuilder.build_rules(
        notes_result.adaptivity,
        primary_component_part,
        parts_layout,
        component_parts
      )

    screen_custom =
      apply_adaptivity_to_screen_custom(notes_result.adaptivity, primary_component_part)

    content = %{
      "custom" => screen_custom,
      "authoring" => %{
        "parts" => authoring_parts,
        "rules" => rules,
        "variablesRequiredForEvaluation" => [],
        "activitiesRequiredForEvaluation" => []
      },
      "partsLayout" => parts_layout
    }

    {:ok, content, warnings}
  end

  defp apply_adaptivity_to_screen_custom(nil, nil), do: @default_screen_custom

  defp apply_adaptivity_to_screen_custom(adaptivity, component_part) do
    custom = @default_screen_custom

    custom =
      if not is_nil(component_part) do
        max_attempt =
          case Map.get(adaptivity || %{}, "maxAttempt") do
            attempt when is_integer(attempt) -> attempt
            attempt when is_binary(attempt) -> String.to_integer(attempt)
            _ -> 3
          end

        Map.put(custom, "maxAttempt", max_attempt)
      else
        custom
      end

    case adaptivity do
      %{"trapStateScoreScheme" => scheme} when is_boolean(scheme) ->
        Map.put(custom, "trapStateScoreScheme", scheme)

      _ ->
        custom
    end
  end

  defp build_parts_layout(slide, media_urls, component_specs) do
    parts = []
    y = 0
    warnings = []

    {parts, y} =
      if slide.title != "" do
        part = PartBuilders.text_flow(slide.title, :h4, y: y)
        {[part | parts], y + 40}
      else
        {parts, y}
      end

    {parts, y, warnings} =
      Enum.reduce(display_paragraphs(slide.paragraphs), {parts, y, warnings}, fn paragraph,
                                                                                 {acc, y_acc,
                                                                                  warn} ->
        part = PartBuilders.text_flow(paragraph, :p, y: y_acc)
        {acc ++ [part], y_acc + 110, warn}
      end)

    {parts, y, warnings, component_parts} =
      Enum.reduce(component_specs, {parts, y, warnings, []}, fn spec,
                                                                {acc, y_acc, warn, components} ->
        case build_component_part(spec, y_acc) do
          {part, height} ->
            {acc ++ [part], y_acc + height, warn, components ++ [part]}

          nil ->
            {acc, y_acc,
             warn ++
               [
                 Warnings.build(:component_build_failed, %{
                   slide_index: slide.index,
                   reason: "unsupported component #{inspect(Map.get(spec, "component"))}"
                 })
               ], components}
        end
      end)

    {parts, _y, warnings} =
      Enum.reduce(slide.images, {parts, y, warnings}, fn image, {acc, y_acc, warn} ->
        case Map.get(media_urls, image.object_id) do
          url when is_binary(url) ->
            part = PartBuilders.image_part(url, y: y_acc)
            {acc ++ [part], y_acc + 220, warn}

          _ ->
            {acc, y_acc,
             warn ++
               [
                 Warnings.build(:media_upload_failed, %{
                   slide_index: slide.index,
                   reason: "missing uploaded url"
                 })
               ]}
        end
      end)

    {parts, component_parts, warnings}
  end

  defp display_paragraphs(paragraphs) do
    Enum.reject(paragraphs, &BracketNotesParser.placeholder_line?/1)
  end

  defp build_component_part(%{"component" => "janus-text-slider"} = spec, y),
    do: {PartBuilders.text_slider_part(spec, y: y), 90}

  defp build_component_part(%{"component" => "janus-input-text"} = spec, y),
    do: {PartBuilders.input_text_part(spec, y: y), 90}

  defp build_component_part(%{"component" => "janus-input-number"} = spec, y),
    do: {PartBuilders.input_number_part(spec, y: y), 90}

  defp build_component_part(%{"component" => "janus-slider"} = spec, y),
    do: {PartBuilders.slider_part(spec, y: y), 100}

  defp build_component_part(%{"component" => "janus-mcq"} = spec, y),
    do: {PartBuilders.mcq_part(spec, y: y), 120}

  defp build_component_part(%{"component" => "janus-dropdown"} = spec, y),
    do: {PartBuilders.dropdown_part(spec, y: y), 100}

  defp build_component_part(_spec, _y), do: nil
end
