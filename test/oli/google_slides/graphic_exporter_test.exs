defmodule Oli.GoogleSlides.GraphicExporterTest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.GraphicExporter

  test "line_svg/2 returns svg markup" do
    element = %{
      "size" => %{
        "width" => %{"magnitude" => 3_000_000.0},
        "height" => %{"magnitude" => 50_000.0}
      }
    }

    svg = GraphicExporter.line_svg(element, %{"lineProperties" => %{}})
    assert svg =~ "<svg"
    assert svg =~ "<line"
  end

  test "shape_svg/2 returns svg markup for ellipses" do
    element = %{
      "size" => %{
        "width" => %{"magnitude" => 1_000_000.0},
        "height" => %{"magnitude" => 500_000.0}
      }
    }

    shape = %{"shapeType" => "ELLIPSE", "shapeProperties" => %{}}
    svg = GraphicExporter.shape_svg(element, shape)
    assert svg =~ "<ellipse"
  end
end
