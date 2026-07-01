defmodule Oli.GoogleSlides.GraphicExporter do
  @moduledoc """
  Generates simple SVG snapshots for non-text slide elements (lines, shapes).
  """

  @default_width 960
  @default_stroke "#4a5568"
  @default_fill "#cbd5e0"

  @spec line_svg(map(), map()) :: binary()
  def line_svg(element, line) do
    width = element_width(element)
    height = max(element_height(element), 8)
    stroke = line_stroke(line)
    weight = line_weight(line)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
      <line x1="0" y1="#{div(height, 2)}" x2="#{width}" y2="#{div(height, 2)}" stroke="#{stroke}" stroke-width="#{weight}" stroke-linecap="round"/>
    </svg>
    """
  end

  @spec shape_svg(map(), map()) :: binary()
  def shape_svg(element, shape) do
    width = element_width(element)
    height = element_height(element)
    fill = shape_fill(shape)
    stroke = shape_stroke(shape)
    shape_type = Map.get(shape, "shapeType", "RECTANGLE")

    body =
      case shape_type do
        "ELLIPSE" ->
          ~s(<ellipse cx="#{div(width, 2)}" cy="#{div(height, 2)}" rx="#{div(width, 2) - 2}" ry="#{div(height, 2) - 2}" fill="#{fill}" stroke="#{stroke}" stroke-width="1"/>)

        "ROUND_RECTANGLE" ->
          ~s(<rect x="1" y="1" width="#{width - 2}" height="#{height - 2}" rx="16" ry="16" fill="#{fill}" stroke="#{stroke}" stroke-width="1"/>)

        _ ->
          ~s(<rect x="1" y="1" width="#{width - 2}" height="#{height - 2}" fill="#{fill}" stroke="#{stroke}" stroke-width="1"/>)
      end

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
      #{body}
    </svg>
    """
  end

  defp element_width(element) do
    case size_magnitude(element, "width") do
      value when is_number(value) and value > 0 ->
        value
        |> emu_to_px()
        |> min(@default_width)
        |> max(120)
        |> trunc()

      _ ->
        @default_width
    end
  end

  defp element_height(element) do
    case size_magnitude(element, "height") do
      value when is_number(value) and value > 0 ->
        value
        |> emu_to_px()
        |> min(400)
        |> max(24)
        |> trunc()

      _ ->
        120
    end
  end

  defp size_magnitude(%{"size" => size}, dimension) do
    case Map.get(size, dimension) do
      %{"magnitude" => magnitude} when is_number(magnitude) -> magnitude
      _ -> nil
    end
  end

  defp size_magnitude(_, _), do: nil

  defp emu_to_px(emu), do: emu / 9525.0

  defp line_stroke(line) do
    line
    |> get_in(["lineProperties", "lineFill", "solidFill", "color"])
    |> color_to_hex(@default_stroke)
  end

  defp line_weight(line) do
    case get_in(line, ["lineProperties", "weight", "magnitude"]) do
      weight when is_number(weight) and weight > 0 -> max(weight, 1)
      _ -> 2
    end
  end

  defp shape_fill(shape) do
    shape
    |> get_in(["shapeProperties", "shapeBackgroundFill", "solidFill", "color"])
    |> color_to_hex(@default_fill)
  end

  defp shape_stroke(shape) do
    shape
    |> get_in(["shapeProperties", "outline", "outlineFill", "solidFill", "color"])
    |> color_to_hex("#718096")
  end

  defp color_to_hex(%{"rgbColor" => rgb}, _default), do: rgb_to_hex(rgb)
  defp color_to_hex(%{"themeColor" => _}, default), do: default
  defp color_to_hex(_, default), do: default

  defp rgb_to_hex(%{"red" => r, "green" => g, "blue" => b}) do
    red = float_channel_to_byte(r)
    green = float_channel_to_byte(g)
    blue = float_channel_to_byte(b)

    "#" <>
      (Integer.to_string(red, 16) |> String.pad_leading(2, "0")) <>
      (Integer.to_string(green, 16) |> String.pad_leading(2, "0")) <>
      (Integer.to_string(blue, 16) |> String.pad_leading(2, "0"))
  end

  defp rgb_to_hex(_), do: @default_fill

  defp float_channel_to_byte(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(255)
    |> round()
  end

  defp float_channel_to_byte(_), do: 0
end
