defmodule Oli.GoogleSlides.MediaIngestor do
  @moduledoc """
  Uploads Google Slides image bytes into the project media library.
  """

  alias Oli.Authoring.MediaLibrary
  alias Oli.GoogleDocs.SlidesClient
  alias Oli.GoogleSlides.PresentationParser.ImageRef
  alias Oli.GoogleSlides.Warnings

  @spec ingest_images([ImageRef.t()], String.t(), String.t(), keyword()) ::
          {:ok, %{String.t() => String.t()}, [map()]}
  def ingest_images(images, project_slug, access_token, opts \\ []) do
    media_library = Keyword.get(opts, :media_library, MediaLibrary)

    {urls, warnings} =
      Enum.reduce(images, {%{}, []}, fn image, {acc, warnings} ->
        case SlidesClient.fetch_image_bytes(image.content_url, access_token) do
          {:ok, bytes} ->
            filename = "slides-#{image.object_id}.png"

            case media_library.add(project_slug, filename, bytes) do
              {:ok, media_item} ->
                {Map.put(acc, image.object_id, media_item.url), warnings}

              {:duplicate, media_item} ->
                {Map.put(acc, image.object_id, media_item.url), warnings}

              {:error, reason} ->
                {acc,
                 warnings ++
                   [
                     Warnings.build(:media_upload_failed, %{
                       slide_index: Map.get(image, :slide_index, 0),
                       reason: inspect(reason)
                     })
                   ]}
            end

          {:error, reason} ->
            {acc,
             warnings ++
               [
                 Warnings.build(:media_upload_failed, %{
                   slide_index: Map.get(image, :slide_index, 0),
                   reason: inspect(reason)
                 })
               ]}
        end
      end)

    {:ok, urls, warnings}
  end
end
