defmodule Oli.GoogleSlides.BracketNotesParser do
  @moduledoc """
  Parses bracket-tagged authoring metadata from slide notes and body text.

  Supports single- and multi-component screens, including mixtures of MCQ,
  dropdowns, numeric sliders, text sliders (binary On/Off), text inputs, and
  number inputs.

  Examples:

      [Multiple choice component]
      [Text slider component: Random Assignment]
      [Text input component: Hypothesis]
      [Correct Answer] Media framing likely influenced trust in police
      [Correct Answer Random Assignment] On
      [Random Assignment Options] Off, On
      [Incorrect Random Assignment Feedback] Try again.
      [Any not modified Feedback] Make sure to complete all settings...
  """

  @component_decl ~r/\[(multiple choice component|dropdown components?|numeric slider component(?:\s*:\s*([^\]]+))?|slider component(?:\s*:\s*([^\]]+))?|text slider component(?:\s*:\s*([^\]]+))?|text input component(?:\s*:\s*([^\]]+))?|number input component(?:\s*:\s*([^\]]+))?)\]/i

  @legacy_component_tag ~r/\[(multiple choice component|dropdown components?|slider component)\]/i

  @tag_pattern ~r/\[([^\]]+)\]\s*([\s\S]*?)(?=\[[^\]]+\]|$)/

  @placeholder_only ~r/^\[[^\]]+\]$/i

  @spec placeholder_line?(String.t()) :: boolean()
  def placeholder_line?(text) do
    trimmed = String.trim(text || "")
    trimmed != "" and Regex.match?(@placeholder_only, trimmed)
  end

  @spec parse(String.t(), map()) :: :not_found | {:ok, map()}
  def parse(text, slide_context \\ %{}) do
    text = String.trim(text || "")

    if text == "" and not component_hint?(slide_context) do
      :not_found
    else
      tags = extract_tags(text)
      declarations = discover_declarations(text, slide_context, tags)
      specs = build_all_specs(declarations, tags, slide_context)

      cond do
        specs != [] ->
          build_result(specs, tags)

        map_size(tags) > 0 and length(mcq_choices(slide_context)) >= 2 ->
          build_result([build_mcq_spec(tags, slide_context)], tags)

        map_size(tags) > 0 ->
          {:ok,
           %{
             component_spec: nil,
             additional_component_specs: [],
             adaptivity: build_adaptivity(tags, %{}),
             warnings: []
           }}

        true ->
          :not_found
      end
    end
  end

  defp build_result(specs, tags) do
    [first | rest] = specs

    {:ok,
     %{
       component_spec: first,
       additional_component_specs: rest,
       adaptivity: build_adaptivity(tags, first, specs),
       warnings: []
     }}
  end

  defp discover_declarations(text, slide_context, tags) do
    from_tags =
      [text | Map.get(slide_context, :paragraphs, [])]
      |> Enum.flat_map(&extract_declarations_from_text/1)
      |> Enum.uniq_by(&declaration_key/1)

    cond do
      from_tags != [] ->
        case from_tags do
          [%{type: :slider, label: nil}] ->
            inferred = infer_text_sliders_from_feedback(tags)
            if inferred != [], do: inferred, else: from_tags

          _ ->
            from_tags
        end

      infer_text_sliders_from_feedback(tags) != [] ->
        infer_text_sliders_from_feedback(tags)

      true ->
        case legacy_single_component(tags, text, slide_context) do
          nil -> []
          type -> [%{type: type, label: nil}]
        end
    end
  end

  defp extract_declarations_from_text(source) do
    source = source || ""

    @component_decl
    |> Regex.scan(source)
    |> Enum.map(fn [full | _] -> parse_declaration_match(full) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_declaration_match(full) do
    case Regex.run(~r/\[(.+)\]/, full, capture: :all_but_first) do
      [inner] -> declaration_from_inner(String.trim(inner))
      _ -> nil
    end
  end

  defp declaration_from_inner(inner) do
    normalized = String.downcase(inner)

    cond do
      normalized == "multiple choice component" ->
        %{type: :mcq, label: nil}

      normalized in ["dropdown components", "dropdown component"] ->
        %{type: :dropdown, label: nil}

      match = Regex.run(~r/^numeric slider component\s*:\s*(.+)$/i, inner) ->
        [_, label] = match
        %{type: :numeric_slider, label: trim_label(label)}

      match = Regex.run(~r/^numeric slider component$/i, inner) ->
        [_] = match
        %{type: :numeric_slider, label: nil}

      match = Regex.run(~r/^text slider component\s*:\s*(.+)$/i, inner) ->
        [_, label] = match
        %{type: :text_slider, label: trim_label(label)}

      match = Regex.run(~r/^text slider component$/i, inner) ->
        [_] = match
        %{type: :text_slider, label: nil}

      match = Regex.run(~r/^text input component\s*:\s*(.+)$/i, inner) ->
        [_, label] = match
        %{type: :text_input, label: trim_label(label)}

      match = Regex.run(~r/^text input component$/i, inner) ->
        [_] = match
        %{type: :text_input, label: nil}

      match = Regex.run(~r/^number input component\s*:\s*(.+)$/i, inner) ->
        [_, label] = match
        %{type: :number_input, label: trim_label(label)}

      match = Regex.run(~r/^number input component$/i, inner) ->
        [_] = match
        %{type: :number_input, label: nil}

      match = Regex.run(~r/^slider component\s*:\s*(.+)$/i, inner) ->
        [_, label] = match
        %{type: :slider, label: trim_label(label)}

      match = Regex.run(~r/^slider component$/i, inner) ->
        [_] = match
        %{type: :slider, label: nil}

      true ->
        nil
    end
  end

  defp trim_label(label) when is_binary(label) do
    case String.trim(label) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_label(_), do: nil

  defp declaration_key(%{type: type, label: label}), do: {type, normalize_text(label || "")}

  defp infer_text_sliders_from_feedback(tags) do
    tags
    |> Enum.flat_map(fn {name, _body} ->
      case Regex.run(~r/^incorrect (.+?) feedback$/, name) do
        [_, part_name] ->
          label = title_case(part_name)

          if label != "" do
            [%{type: :text_slider, label: label}]
          else
            []
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq_by(&declaration_key/1)
  end

  defp build_all_specs(declarations, tags, slide_context) do
    declarations
    |> Enum.flat_map(fn decl -> build_specs_for_declaration(decl, tags, slide_context) end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_specs_for_declaration(%{type: :mcq}, tags, slide_context) do
    case build_mcq_spec(tags, slide_context) do
      nil -> []
      spec -> [spec]
    end
  end

  defp build_specs_for_declaration(%{type: :dropdown}, tags, slide_context) do
    build_dropdown_specs(tags, slide_context)
  end

  defp build_specs_for_declaration(%{type: :numeric_slider, label: label}, tags, _slide_context) do
    case build_numeric_slider_spec(label, tags) do
      nil -> []
      spec -> [spec]
    end
  end

  defp build_specs_for_declaration(%{type: :slider, label: label}, tags, slide_context) do
    cond do
      label != nil ->
        case build_text_slider_spec(label, tags, slide_context) do
          nil -> []
          spec -> [spec]
        end

      numeric_slider_answer?(tags) ->
        case build_numeric_slider_spec(nil, tags) do
          nil -> []
          spec -> [spec]
        end

      true ->
        case build_numeric_slider_spec(nil, tags) do
          nil -> []
          spec -> [spec]
        end
    end
  end

  defp build_specs_for_declaration(%{type: :text_slider, label: label}, tags, slide_context) do
    resolved_label = label || "Slider"

    case build_text_slider_spec(resolved_label, tags, slide_context) do
      nil -> []
      spec -> [spec]
    end
  end

  defp build_specs_for_declaration(%{type: :text_input, label: label}, tags, _slide_context) do
    resolved_label = label || "Input"

    case build_text_input_spec(resolved_label, tags) do
      nil -> []
      spec -> [spec]
    end
  end

  defp build_specs_for_declaration(%{type: :number_input, label: label}, tags, _slide_context) do
    resolved_label = label || "Number"

    case build_number_input_spec(resolved_label, tags) do
      nil -> []
      spec -> [spec]
    end
  end

  defp build_specs_for_declaration(_, _, _), do: []

  defp extract_tags(text) do
    @tag_pattern
    |> Regex.scan(text)
    |> Enum.reduce(%{}, fn [_full, raw_name, raw_body], acc ->
      name = normalize_tag_name(raw_name)
      body = clean_tag_body(raw_body)

      if name != "" and body != "" do
        Map.update(acc, name, [body], fn existing -> existing ++ [body] end)
      else
        acc
      end
    end)
    |> Enum.map(fn {name, bodies} -> {name, Enum.join(bodies, "\n")} end)
    |> Map.new()
  end

  defp normalize_tag_name(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end

  defp clean_tag_body(body) do
    body
    |> String.trim()
    |> String.replace(~r/^\[Go to subscreen\]\s*/i, "")
    |> String.trim()
  end

  defp component_hint?(slide_context) do
    slide_context
    |> Map.get(:paragraphs, [])
    |> Enum.any?(&component_placeholder?/1)
  end

  defp component_placeholder?(text) do
    Regex.match?(@component_decl, text || "") or Regex.match?(@legacy_component_tag, text || "")
  end

  defp legacy_single_component(tags, text, slide_context) do
    cond do
      tag_indicates?(tags, "multiple choice component") ->
        :mcq

      tag_indicates?(tags, "dropdown component") or tag_indicates?(tags, "dropdown components") ->
        :dropdown

      tag_indicates?(tags, "slider component") ->
        :slider

      Regex.match?(@legacy_component_tag, text) ->
        case Regex.run(@legacy_component_tag, text, capture: :all_but_first) do
          [label] -> legacy_type_from_label(String.downcase(label))
          _ -> nil
        end

      Enum.any?(Map.get(slide_context, :paragraphs, []), &component_placeholder?/1) ->
        slide_context
        |> Map.get(:paragraphs, [])
        |> Enum.find_value(fn paragraph ->
          case Regex.run(@legacy_component_tag, paragraph || "", capture: :all_but_first) do
            [label] -> legacy_type_from_label(String.downcase(label))
            _ -> nil
          end
        end)

      map_size(tags) > 0 and length(Map.get(slide_context, :list_items, [])) >= 2 ->
        :mcq

      true ->
        nil
    end
  end

  defp legacy_type_from_label("multiple choice component"), do: :mcq
  defp legacy_type_from_label("dropdown components"), do: :dropdown
  defp legacy_type_from_label("dropdown component"), do: :dropdown
  defp legacy_type_from_label("slider component"), do: :slider
  defp legacy_type_from_label(_), do: nil

  defp tag_indicates?(tags, name), do: Map.has_key?(tags, name)

  defp build_mcq_spec(tags, slide_context) do
    choices = mcq_choices(slide_context)
    correct_text = Map.get(tags, "correct answer", "")

    if choices == [] do
      nil
    else
      %{
        "component" => "janus-mcq",
        "label" => mcq_label(slide_context, tags),
        "choices" => choices,
        "correct" => resolve_choice_index(correct_text, choices),
        "correctFeedback" => Map.get(tags, "correct feedback"),
        "incorrectFeedback" => default_incorrect_feedback(tags)
      }
    end
  end

  defp build_dropdown_specs(tags, slide_context) do
    mappings = all_dropdown_mappings(slide_context)

    if length(mappings) >= 2 do
      options = mappings |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      Enum.map(mappings, fn {left, right} ->
        %{
          "component" => "janus-dropdown",
          "label" => left,
          "prompt" => "Select an option",
          "optionLabels" => options,
          "correct" => Enum.find_index(options, &(&1 == right)) || 0,
          "correctFeedback" => Map.get(tags, "correct feedback"),
          "incorrectFeedback" => default_incorrect_feedback(tags)
        }
      end)
    else
      case build_single_dropdown_spec(tags, slide_context) do
        nil -> []
        spec -> [spec]
      end
    end
  end

  defp build_single_dropdown_spec(tags, slide_context) do
    {prompt, options, correct_index} = dropdown_from_context(slide_context, tags)

    if options == [] do
      nil
    else
      %{
        "component" => "janus-dropdown",
        "label" => prompt,
        "prompt" => "Select an option",
        "optionLabels" => options,
        "correct" => correct_index,
        "correctFeedback" => Map.get(tags, "correct feedback"),
        "incorrectFeedback" => default_incorrect_feedback(tags)
      }
    end
  end

  defp build_numeric_slider_spec(label, tags) do
    answer_text =
      part_tag_value(tags, label, ["correct answer"]) || Map.get(tags, "correct answer")

    case answer_text do
      nil ->
        nil

      text ->
        case Regex.run(~r/(\d+)\s*(?:-|–|to)\s*(\d+)/i, text) do
          [_, min, max] ->
            %{
              "component" => "janus-slider",
              "label" => label || Map.get(tags, "label", "Select a value"),
              "min" => String.to_integer(min),
              "max" => String.to_integer(max),
              "step" => 1,
              "correct" => String.to_integer(min),
              "correctFeedback" => Map.get(tags, "correct feedback"),
              "incorrectFeedback" => default_incorrect_feedback(tags)
            }

          _ ->
            nil
        end
    end
  end

  defp numeric_slider_answer?(tags) do
    case Map.get(tags, "correct answer") do
      nil -> false
      text -> Regex.match?(~r/(\d+)\s*(?:-|–|to)\s*(\d+)/i, text)
    end
  end

  defp build_text_slider_spec(label, tags, _slide_context) do
    options = text_slider_options(label, tags)
    correct_text = part_tag_value(tags, label, ["correct answer"])

    correct_index =
      if correct_text do
        resolve_choice_index(correct_text, options)
      else
        0
      end

    %{
      "component" => "janus-text-slider",
      "label" => label,
      "partKey" => normalize_text(label),
      "sliderOptionLabels" => options,
      "correct" => correct_index,
      "correctFeedback" => Map.get(tags, "correct feedback"),
      "incorrectFeedback" =>
        part_incorrect_feedback(tags, label) || default_incorrect_feedback(tags)
    }
  end

  defp build_text_input_spec(label, tags) do
    correct_text = part_tag_value(tags, label, ["correct answer"])

    %{
      "component" => "janus-input-text",
      "label" => label,
      "partKey" => normalize_text(label),
      "prompt" => Map.get(tags, "prompt", "enter some text"),
      "correctAnswer" => %{
        "minimumLength" =>
          if(correct_text, do: String.length(String.trim(correct_text)), else: 1),
        "mustContain" => correct_text || "",
        "mustNotContain" => ""
      },
      "correctFeedback" => Map.get(tags, "correct feedback"),
      "incorrectFeedback" =>
        part_incorrect_feedback(tags, label) || default_incorrect_feedback(tags)
    }
  end

  defp build_number_input_spec(label, tags) do
    correct_text = part_tag_value(tags, label, ["correct answer"])

    correct =
      case correct_text do
        nil -> 0
        text -> parse_number(text) || 0
      end

    %{
      "component" => "janus-input-number",
      "label" => label,
      "partKey" => normalize_text(label),
      "prompt" => Map.get(tags, "prompt", "enter a number"),
      "correct" => correct,
      "correctFeedback" => Map.get(tags, "correct feedback"),
      "incorrectFeedback" =>
        part_incorrect_feedback(tags, label) || default_incorrect_feedback(tags)
    }
  end

  defp text_slider_options(label, tags) do
    case part_tag_value(tags, label, ["options"]) do
      nil ->
        default_binary_options(label)

      options_text ->
        options_text
        |> String.split(~r/[,|\/]/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> case do
          [] -> default_binary_options(label)
          options -> options
        end
    end
  end

  defp default_binary_options(label) do
    norm = normalize_text(label)

    cond do
      String.contains?(norm, "group type") -> ["Pre-existing", "Constructed"]
      String.contains?(norm, "pre test") or String.contains?(norm, "pretest") -> ["No", "Yes"]
      String.contains?(norm, "treatment") -> ["No", "Yes"]
      true -> ["Off", "On"]
    end
  end

  defp part_tag_value(tags, label, suffixes) when is_list(suffixes) do
    keys = part_tag_keys(label, suffixes)

    Enum.find_value(keys, fn key -> Map.get(tags, key) end)
  end

  defp part_tag_keys(nil, suffixes), do: suffixes

  defp part_tag_keys(label, suffixes) do
    norm = normalize_text(label)

    Enum.flat_map(suffixes, fn suffix ->
      [
        "#{suffix}: #{norm}",
        "#{suffix} #{norm}",
        "#{norm} #{suffix}"
      ]
    end)
  end

  defp part_incorrect_feedback(tags, label) do
    norm = normalize_text(label)

    tags
    |> Enum.find_value(fn {name, body} ->
      if Regex.match?(~r/^incorrect .+ feedback$/, name) do
        part_key =
          name
          |> String.replace_prefix("incorrect ", "")
          |> String.replace_suffix(" feedback", "")

        if normalize_text(part_key) == norm, do: body
      end
    end)
  end

  defp all_dropdown_mappings(slide_context) do
    slide_context
    |> Map.get(:paragraphs, [])
    |> Enum.flat_map(fn paragraph ->
      paragraph
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.run(~r/^(.+?)\s*(?:→|->)\s*(.+)$/, String.trim(line)) do
          [_, left, right] -> [{String.trim(left), String.trim(right)}]
          _ -> []
        end
      end)
    end)
  end

  defp build_adaptivity(tags, component_spec, all_specs \\ []) do
    require_all_modified? =
      Map.has_key?(tags, "any not modified feedback") or
        (Enum.any?(all_specs, &(&1["component"] == "janus-text-slider")) and
           length(Enum.filter(all_specs, &(&1["component"] == "janus-text-slider"))) > 1)

    %{
      "score" => 0,
      "correctFeedback" =>
        Map.get(tags, "correct feedback") || Map.get(component_spec, "correctFeedback"),
      "incorrectFeedback" =>
        default_incorrect_feedback(tags) || Map.get(component_spec, "incorrectFeedback"),
      "blankFeedback" => blank_feedback(tags),
      "onCorrect" => navigation_from_feedback(Map.get(tags, "correct feedback", "navigate next")),
      "onIncorrect" => "show feedback",
      "maxAttempt" => 3,
      "trapStateScoreScheme" => true,
      "requireAllModified" => require_all_modified?,
      "commonErrors" => common_errors(tags)
    }
  end

  defp mcq_choices(slide_context) do
    case Map.get(slide_context, :list_items, []) do
      items when length(items) >= 2 ->
        items

      _ ->
        slide_context
        |> Map.get(:paragraphs, [])
        |> Enum.flat_map(&choices_from_paragraph/1)
        |> Enum.uniq()
    end
  end

  defp choices_from_paragraph(paragraph) do
    paragraph
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^([•\-\*]|\d+\.)\s+(.+)$/, line) do
        [_, _, choice] -> [String.trim(choice)]
        _ -> []
      end
    end)
  end

  defp mcq_label(slide_context, _tags) do
    question =
      slide_context
      |> Map.get(:paragraphs, [])
      |> Enum.find(fn paragraph ->
        trimmed = String.trim(paragraph)
        trimmed != "" and String.ends_with?(trimmed, "?")
      end)

    cond do
      is_binary(question) ->
        String.trim(question)

      Map.get(slide_context, :title, "") != "" ->
        Map.get(slide_context, :title)

      true ->
        "Select one"
    end
  end

  defp dropdown_from_context(slide_context, tags) do
    mappings =
      slide_context
      |> Map.get(:paragraphs, [])
      |> Enum.flat_map(&dropdown_mappings_from_line/1)

    options = mappings |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    prompt = dropdown_prompt(slide_context)

    correct_index =
      case Map.get(tags, "correct answer", "") do
        "" ->
          0

        answer_text ->
          resolve_dropdown_correct(answer_text, mappings, options)
      end

    {prompt, options, correct_index}
  end

  defp dropdown_mappings_from_line(line) do
    line
    |> String.split("\n")
    |> Enum.flat_map(fn text ->
      case Regex.run(~r/^(.+?)\s*(?:→|->)\s*(.+)$/, String.trim(text)) do
        [_, _left, right] -> [{String.trim(text), String.trim(right)}]
        _ -> []
      end
    end)
  end

  defp dropdown_prompt(slide_context) do
    slide_context
    |> Map.get(:paragraphs, [])
    |> Enum.find(fn paragraph ->
      String.contains?(String.downcase(paragraph), "match each") or
        String.contains?(String.downcase(paragraph), "variables")
    end)
    |> case do
      nil -> "Select the correct option"
      prompt -> String.trim(prompt)
    end
  end

  defp resolve_dropdown_correct(answer_text, mappings, options) do
    answer_norm = normalize_text(answer_text)

    cond do
      Enum.any?(mappings, fn {_label, right} ->
        String.contains?(answer_norm, normalize_text(right))
      end) ->
        {_label, right} =
          Enum.find(mappings, fn {_label, right} ->
            String.contains?(answer_norm, normalize_text(right))
          end)

        Enum.find_index(options, &(&1 == right)) || 0

      true ->
        resolve_choice_index(answer_text, options)
    end
  end

  defp resolve_choice_index(correct_text, choices) do
    correct_norm = normalize_text(correct_text)

    case Enum.find_index(choices, fn choice ->
           choice_norm = normalize_text(choice)

           choice_norm == correct_norm or
             String.contains?(correct_norm, choice_norm) or
             String.contains?(choice_norm, correct_norm)
         end) do
      nil -> 0
      index -> index
    end
  end

  defp normalize_text(text) when not is_binary(text), do: ""

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp title_case(str) do
    str
    |> String.split(~r/\s+/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp parse_number(text) do
    case Float.parse(String.trim(text)) do
      {num, _} -> trunc(num)
      :error -> nil
    end
  end

  defp default_incorrect_feedback(tags) do
    header = Map.get(tags, "header for incorrect feedback")
    body = Map.get(tags, "incorrect feedback")

    cond do
      header && body -> "#{header} #{body}"
      header -> header
      body -> body
      true -> "Incorrect, please try again."
    end
  end

  defp blank_feedback(tags) do
    Map.get(tags, "blank feedback") ||
      Map.get(tags, "any not modified feedback") ||
      Map.get(tags, "any not modified feedback ")
  end

  defp navigation_from_feedback(feedback) do
    if Regex.match?(~r/go to subscreen|proceed|navigate/i, feedback || "") do
      "navigate next"
    else
      "navigate next"
    end
  end

  defp common_errors(tags) do
    numbered =
      tags
      |> Enum.flat_map(fn {name, body} ->
        case Regex.run(~r/^incorrect (\d+)$/, name) do
          [_, option] -> [%{"option" => String.to_integer(option), "feedback" => body}]
          _ -> []
        end
      end)

    named =
      tags
      |> Enum.flat_map(fn {name, body} ->
        cond do
          Regex.match?(~r/^incorrect \d+$/, name) ->
            []

          String.starts_with?(name, "incorrect ") and String.ends_with?(name, " feedback") ->
            part_key =
              name
              |> String.replace_prefix("incorrect ", "")
              |> String.replace_suffix(" feedback", "")
              |> String.trim()

            if part_key != "" do
              [%{"partKey" => part_key, "feedback" => body}]
            else
              []
            end

          String.starts_with?(name, "incorrect ") ->
            [%{"name" => name, "feedback" => body}]

          true ->
            []
        end
      end)

    numbered ++ named
  end
end
