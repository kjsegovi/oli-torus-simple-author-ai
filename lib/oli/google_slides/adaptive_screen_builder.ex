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
      slide.content_blocks
      |> content_blocks_for_render(component_specs)
      |> render_content_blocks(parts, y, warnings, media_urls, slide.index)

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

    {parts, component_parts, warnings}
  end

  defp content_blocks_for_render(content_blocks, component_specs) when is_list(content_blocks) do
    skip_lists? =
      Enum.any?(component_specs, fn spec ->
        Map.get(spec, "component") in ["janus-mcq", "janus-dropdown"]
      end)

    if skip_lists? do
      Enum.reject(content_blocks, &match?(%{type: "list"}, &1))
    else
      content_blocks
    end
  end

  defp content_blocks_for_render(_, _), do: []

  defp render_content_blocks(content_blocks, parts, y, warnings, media_urls, slide_index) do
    Enum.reduce(content_blocks, {parts, y, warnings}, fn block, {acc, y_acc, warn} ->
      case block do
        %{type: "paragraph", text: text} ->
          if BracketNotesParser.placeholder_line?(text) do
            {acc, y_acc, warn}
          else
            part = PartBuilders.text_flow(text, :p, y: y_acc)
            {acc ++ [part], y_acc + 110, warn}
          end

        %{type: "heading", tag: tag, text: text} ->
          part = PartBuilders.text_flow(text, heading_tag(tag), y: y_acc)
          {acc ++ [part], y_acc + heading_offset(tag), warn}

        %{type: "table", text: text} ->
          part = PartBuilders.text_flow(text, :p, y: y_acc)
          {acc ++ [part], y_acc + 110, warn}

        %{type: "list", items: items, list_type: list_type} ->
          visible_items = Enum.reject(items, &BracketNotesParser.placeholder_line?/1)

          if visible_items == [] do
            {acc, y_acc, warn}
          else
            part = PartBuilders.list_flow(visible_items, list_type, y: y_acc)
            height = max(length(visible_items) * 28, 48)
            {acc ++ [part], y_acc + height + 12, warn}
          end

        %{type: "image", ref: image} = block ->
          case Map.get(media_urls, image.object_id) do
            url when is_binary(url) ->
              height = image_part_height(image)
              alt = Map.get(block, :alt, "Slide image")

              part = PartBuilders.image_part(url, y: y_acc, height: height, alt: alt)
              {acc ++ [part], y_acc + height + 20, warn}

            _ ->
              {acc, y_acc,
               warn ++
                 [
                   Warnings.build(:media_upload_failed, %{
                     slide_index: slide_index,
                     reason: "missing uploaded url"
                   })
                 ]}
          end

        %{type: "video", src: src} = block ->
          height = Map.get(block, :height, 280)
          alt = Map.get(block, :alt, "Slide video")
          part = PartBuilders.video_part(src, y: y_acc, height: height, alt: alt)
          {acc ++ [part], y_acc + height + 20, warn}

        %{type: "word_art", text: text} ->
          part = PartBuilders.text_flow(text, :h1, y: y_acc)
          {acc ++ [part], y_acc + 48, warn}

        _ ->
          {acc, y_acc, warn}
      end
    end)
  end

  defp heading_tag("h1"), do: :h1
  defp heading_tag("h2"), do: :h2
  defp heading_tag("h3"), do: :h3
  defp heading_tag("h4"), do: :h4
  defp heading_tag("h5"), do: :h5
  defp heading_tag("h6"), do: :h6
  defp heading_tag(_), do: :p

  defp heading_offset("h1"), do: 44
  defp heading_offset("h2"), do: 40
  defp heading_offset("h3"), do: 36
  defp heading_offset("h4"), do: 32
  defp heading_offset("h5"), do: 28
  defp heading_offset("h6"), do: 24
  defp heading_offset(_), do: 32

  @slides_emu_per_px 9525.0

  defp image_part_height(%{height: height}) when is_number(height) and height > 0 do
    height
    |> Kernel./(@slides_emu_per_px)
    |> min(400.0)
    |> max(80.0)
    |> trunc()
  end

  defp image_part_height(_), do: 200

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

  defp build_component_part(%{"component" => "janus-capi-iframe"} = spec, y),
    do: {PartBuilders.iframe_part(spec, y: y), 340}

  defp build_component_part(_spec, _y), do: nil
end
