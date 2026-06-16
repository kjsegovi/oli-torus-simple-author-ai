defmodule Oli.GoogleDocs.SlidesClientTest do
  use Oli.DataCase, async: true

  alias Oli.GoogleDocs.SlidesClient

  test "get_presentation_id/1 extracts id from standard url" do
    url = "https://docs.google.com/presentation/d/abc123XYZ/edit#slide=id.p"

    assert {:ok, "abc123XYZ"} = SlidesClient.get_presentation_id(url)
  end

  test "get_presentation_id/1 rejects invalid urls" do
    assert {:error, :invalid_presentation_url} =
             SlidesClient.get_presentation_id("https://example.com/not-slides")
  end

  test "get_slides/1 returns slide list" do
    json = %{"slides" => [%{"objectId" => "s1"}, %{"objectId" => "s2"}]}
    assert length(SlidesClient.get_slides(json)) == 2
  end
end
