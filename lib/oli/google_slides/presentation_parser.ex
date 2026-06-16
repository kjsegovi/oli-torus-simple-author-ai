defmodule Oli.GoogleSlides.PresentationParser do
  @moduledoc """
  Parses raw Google Slides API JSON into intermediate slide structs.
  """

  alias Oli.GoogleDocs.SlidesClient

  defmodule Slide do
    @moduledoc false
    defstruct [
      :index,
      :object_id,
      :title,
      :title_from_placeholder,
      :paragraphs,
      :list_items,
      :images,
      :raw_elements,
      :notes_text
    ]
  end

  defmodule ImageRef do
    @moduledoc false
    defstruct [:object_id, :content_url, :width, :height]
  end

  @spec parse(map(), keyword()) :: {:ok, [Slide.t()], [map()]}
  def parse(presentation_json, opts \\ []) do
    access_token = Keyword.get(opts, :access_token)
    warnings = []

    slides =
      presentation_json
      |> SlidesClient.get_slides()
      |> Enum.with_index(1)
      |> Enum.map(fn {slide, index} ->
        build_slide(slide, index, presentation_json, access_token)
      end)

    {:ok, slides, warnings}
  end

  defp build_slide(slide, index, presentation_json, access_token) do
    elements = Map.get(slide, "pageElements", [])
    {title, title_from_placeholder, text_blocks} = extract_text_blocks(elements)
    {paragraphs, list_items} = split_paragraphs_and_lists(text_blocks)
    images = extract_images(elements)

    notes_text =
      case access_token do
        token when is_binary(token) ->
          case SlidesClient.get_speaker_notes_text(slide, presentation_json, token) do
            {:ok, text} -> text
            _ -> ""
          end

        _ ->
          ""
      end

    %Slide{
      index: index,
      object_id: Map.get(slide, "objectId"),
      title: title,
      title_from_placeholder: title_from_placeholder,
      paragraphs: paragraphs,
      list_items: list_items,
      images: images,
      raw_elements: elements,
      notes_text: notes_text
    }
  end

  defp extract_text_blocks(elements) do
    {title, title_from_placeholder, blocks} =
      Enum.reduce(elements, {"", false, []}, fn element, {title, from_ph, blocks} ->
        case text_from_element(element) do
          {:title, text} ->
            if title == "" do
              {text, true, blocks}
            else
              {title, from_ph, blocks ++ [text]}
            end

          {:body, text} ->
            {title, from_ph, blocks ++ [text]}

          :skip ->
            {title, from_ph, blocks}
        end
      end)

    blocks = Enum.reject(blocks, &(String.trim(&1) == ""))
    {title, title_from_placeholder, blocks}
  end

  defp text_from_element(%{"shape" => %{"placeholder" => %{"type" => "TITLE"}, "text" => text}}) do
    case extract_shape_text(text) do
      "" -> :skip
      content -> {:title, content}
    end
  end

  defp text_from_element(%{"shape" => %{"text" => text}}) do
    case extract_shape_text(text) do
      "" -> :skip
      content -> {:body, content}
    end
  end

  defp text_from_element(%{"table" => table}) do
    case extract_table_text(table) do
      "" -> :skip
      content -> {:body, content}
    end
  end

  defp text_from_element(_), do: :skip

  defp extract_shape_text(%{"textElements" => elements}) when is_list(elements) do
    elements
    |> Enum.flat_map(fn
      %{"textRun" => %{"content" => content}} when is_binary(content) -> [content]
      _ -> []
    end)
    |> Enum.join("")
    |> String.trim()
  end

  defp extract_shape_text(_), do: ""

  defp extract_table_text(%{"tableRows" => rows}) when is_list(rows) do
    rows
    |> Enum.map(fn
      %{"tableCells" => cells} ->
        cells
        |> Enum.map(fn
          %{"text" => text} -> extract_shape_text(text)
          _ -> ""
        end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" | ")

      _ ->
        ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_table_text(_), do: ""

  defp split_paragraphs_and_lists(text_blocks) do
    Enum.reduce(text_blocks, {[], []}, fn block, {paragraphs, list_items} ->
      {block_paragraphs, block_list_items} = split_list_items(block)
      {paragraphs ++ block_paragraphs, list_items ++ block_list_items}
    end)
  end

  defp split_list_items(text) do
    lines =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {non_list, list} =
      Enum.split_with(lines, fn line ->
        not Regex.match?(~r/^([•\-\*]|\d+\.)\s+/, line)
      end)

    list_items =
      list
      |> Enum.map(fn line ->
        line
        |> String.replace(~r/^([•\-\*]|\d+\.)\s+/, "")
        |> String.trim()
      end)
      |> Enum.reject(&(&1 == ""))

    paragraphs = if non_list == [], do: [], else: [Enum.join(non_list, "\n")]
    {paragraphs, list_items}
  end

  defp extract_images(elements) do
    Enum.flat_map(elements, fn
      %{"objectId" => object_id, "image" => %{"contentUrl" => url}} = element ->
        size = Map.get(element, "size", %{})
        transform = Map.get(element, "transform", %{})

        [
          %ImageRef{
            object_id: object_id,
            content_url: url,
            width: size_value(size, "width"),
            height: size_value(size, "height")
          }
          |> Map.put(:transform, transform)
        ]

      _ ->
        []
    end)
  end

  defp size_value(%{"width" => %{"magnitude" => magnitude}}, _), do: magnitude
  defp size_value(%{"height" => %{"magnitude" => magnitude}}, "height"), do: magnitude
  defp size_value(_, _), do: nil
end
