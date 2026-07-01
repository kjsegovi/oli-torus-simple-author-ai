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
        case ingest_single_image(image, project_slug, access_token, media_library) do
          {:ok, object_id, url} ->
            {Map.put(acc, object_id, url), warnings}

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

  defp ingest_single_image(
         %{inline_bytes: bytes} = image,
         project_slug,
         _access_token,
         media_library
       )
       when is_binary(bytes) and bytes != "" do
    object_id = image.object_id
    extension = image_extension(image.inline_content_type)
    filename = "slides-#{object_id}#{extension}"

    case media_library.add(project_slug, filename, bytes) do
      {:ok, media_item} -> {:ok, object_id, media_item.url}
      {:duplicate, media_item} -> {:ok, object_id, media_item.url}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ingest_single_image(image, project_slug, access_token, media_library) do
    case SlidesClient.fetch_image_bytes(image.content_url, access_token) do
      {:ok, bytes, content_type} ->
        filename = "slides-#{image.object_id}#{image_extension(content_type)}"

        case media_library.add(project_slug, filename, bytes) do
          {:ok, media_item} ->
            {:ok, image.object_id, media_item.url}

          {:duplicate, media_item} ->
            {:ok, image.object_id, media_item.url}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp image_extension("image/svg+xml"), do: ".svg"

  defp image_extension(content_type) when is_binary(content_type) do
    case String.downcase(content_type) do
      "image/jpeg" -> ".jpg"
      "image/jpg" -> ".jpg"
      "image/gif" -> ".gif"
      "image/webp" -> ".webp"
      "image/svg+xml" -> ".svg"
      _ -> ".png"
    end
  end

  defp image_extension(_), do: ".png"
end
