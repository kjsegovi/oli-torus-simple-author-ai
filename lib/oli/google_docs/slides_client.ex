defmodule Oli.GoogleDocs.SlidesClient do
  @moduledoc """
  HTTP client for the Google Slides / Presentations API.

  Accepts project-scoped service account credentials (via `Oli.GoogleSlides.Credentials`)
  with an optional global env fallback for local development.
  """

  require Logger

  alias HTTPoison.Response
  alias Oli.GoogleSlides.Credentials

  @slides_api_url "https://slides.googleapis.com/v1/presentations"
  @slides_scope "https://www.googleapis.com/auth/presentations.readonly"

  @type credentials :: map()
  @type presentation_json :: map()

  def get_presentation_id(url) do
    with [_, id] <- Regex.run(~r{/presentation/d/([^/]+)}, url) do
      {:ok, id}
    else
      _ -> {:error, :invalid_presentation_url}
    end
  end

  @spec fetch_access_token(credentials()) :: {:ok, String.t()} | {:error, term()}
  def fetch_access_token(credentials) when is_map(credentials) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    token_uri = credentials["token_uri"] || "https://oauth2.googleapis.com/token"

    claims = %{
      "iss" => credentials["client_email"],
      "scope" => @slides_scope,
      "aud" => token_uri,
      "iat" => now,
      "exp" => now + 360
    }

    assertion =
      JOSE.JWT.sign(
        JOSE.JWK.from_pem(credentials["private_key"]),
        %{"alg" => "RS256", "kid" => credentials["private_key_id"], "typ" => "JWT"},
        claims
      )
      |> JOSE.JWS.compact()
      |> elem(1)

    body =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => assertion
      })

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"}
    ]

    with {:ok, %Response{status_code: 200, body: body}} <-
           Oli.HTTP.http().post(token_uri, body, headers, []),
         {:ok, %{"access_token" => access_token}} <- Jason.decode(body) do
      {:ok, access_token}
    else
      {:ok, %Response{status_code: status, body: body}} ->
        {:error, {:token_http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_presentation_json(String.t(), integer() | credentials()) ::
          {:ok, presentation_json()} | {:error, term()}
  def fetch_presentation_json(presentation_url, project_id) when is_integer(project_id) do
    with {:ok, credentials} <- Credentials.get_credentials_map(project_id) do
      fetch_presentation_json(presentation_url, credentials)
    end
  end

  def fetch_presentation_json(presentation_url, credentials) when is_map(credentials) do
    with {:ok, access_token} <- fetch_access_token(credentials) do
      fetch_presentation_json(presentation_url, access_token, credentials)
    end
  end

  @spec fetch_presentation_json(String.t(), String.t(), credentials()) ::
          {:ok, presentation_json()} | {:error, term()}
  def fetch_presentation_json(presentation_url, access_token, _credentials) do
    with {:ok, presentation_id} <- get_presentation_id(presentation_url),
         url <- "#{@slides_api_url}/#{presentation_id}",
         headers <- auth_headers(access_token),
         {:ok, %Response{status_code: 200, body: body}} <- Oli.HTTP.http().get(url, headers, []),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      {:ok, %Response{status_code: 403, body: body}} ->
        log_presentation_access_failure(403, body)
        {:error, classify_access_error(body)}

      {:ok, %Response{status_code: 404, body: body}} ->
        log_presentation_access_failure(404, body)
        {:error, :presentation_not_accessible}

      {:ok, %Response{status_code: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec accessible?(String.t(), integer()) :: {:ok, String.t()} | {:error, term()}
  def accessible?(presentation_url, project_id) do
    with {:ok, credentials} <- Credentials.get_credentials_map(project_id),
         {:ok, presentation_id} <- get_presentation_id(presentation_url),
         {:ok, access_token} <- fetch_access_token(credentials) do
      url = "#{@slides_api_url}/#{presentation_id}"
      headers = auth_headers(access_token)

      case Oli.HTTP.http().get(url, headers, []) do
        {:ok, %Response{status_code: 200}} ->
          {:ok, presentation_id}

        {:ok, %Response{status_code: 403}} ->
          {:error, :presentation_not_accessible}

        {:ok, %Response{status_code: 404}} ->
          {:error, :presentation_not_accessible}

        {:ok, %Response{status_code: status, body: body}} ->
          {:error, {:http_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec get_slides(presentation_json()) :: [map()]
  def get_slides(%{"slides" => slides}) when is_list(slides), do: slides
  def get_slides(_), do: []

  @spec get_presentation_title(presentation_json()) :: String.t()
  def get_presentation_title(%{"title" => title}) when is_binary(title), do: title
  def get_presentation_title(_), do: "Imported Slides Lesson"

  @spec fetch_page_json(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def fetch_page_json(presentation_id, page_object_id, access_token) do
    url = "#{@slides_api_url}/#{presentation_id}/pages/#{page_object_id}"
    headers = auth_headers(access_token)

    with {:ok, %Response{status_code: 200, body: body}} <- Oli.HTTP.http().get(url, headers, []),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      {:ok, %Response{status_code: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_speaker_notes_text(map(), presentation_json(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def get_speaker_notes_text(slide, presentation_json, access_token) do
    with {:ok, presentation_id} <- presentation_id_from_json(presentation_json),
         {:ok, notes_page_id} <- notes_page_id(slide),
         {:ok, page} <- fetch_page_json(presentation_id, notes_page_id, access_token) do
      {:ok, extract_text_from_page(page)}
    else
      {:error, :no_notes} -> {:ok, ""}
      error -> error
    end
  end

  @spec fetch_image_bytes(String.t(), String.t()) ::
          {:ok, binary(), String.t() | nil} | {:error, term()}
  def fetch_image_bytes(content_url, access_token) do
    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"accept", "*/*"}
    ]

    case Oli.HTTP.http().get(content_url, headers, []) do
      {:ok, %Response{status_code: 200, body: body, headers: response_headers}}
      when is_binary(body) ->
        {:ok, body, content_type_from_headers(response_headers)}

      {:ok, %Response{status_code: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_type_from_headers(headers) do
    headers
    |> Enum.find_value(fn
      {"content-type", value} -> value |> String.split(";") |> hd() |> String.trim()
      {"Content-Type", value} -> value |> String.split(";") |> hd() |> String.trim()
      _ -> nil
    end)
  end

  defp auth_headers(access_token) do
    [
      {"authorization", "Bearer #{access_token}"},
      {"accept", "application/json"}
    ]
  end

  defp log_presentation_access_failure(status, body) do
    Logger.warning(
      "Google Slides presentation access failed with status #{status}: #{presentation_error_summary(body)}"
    )
  end

  defp presentation_error_summary(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} when is_binary(message) ->
        message

      _ ->
        String.slice(body, 0, 200)
    end
  end

  defp presentation_error_summary(_), do: "unknown error"

  defp classify_access_error(body) do
    summary = presentation_error_summary(body)

    if slides_api_disabled_message?(summary) do
      :google_slides_api_disabled
    else
      :presentation_not_accessible
    end
  end

  defp slides_api_disabled_message?(summary) when is_binary(summary) do
    String.contains?(summary, "Google Slides API has not been used") or
      String.contains?(summary, "slides.googleapis.com")
  end

  defp slides_api_disabled_message?(_), do: false

  defp presentation_id_from_json(%{"presentationId" => id}) when is_binary(id), do: {:ok, id}

  defp presentation_id_from_json(_), do: {:error, :missing_presentation_id}

  defp notes_page_id(%{"slideProperties" => %{"notesPage" => %{"objectId" => id}}})
       when is_binary(id),
       do: {:ok, id}

  defp notes_page_id(_), do: {:error, :no_notes}

  defp extract_text_from_page(%{"pageElements" => elements}) when is_list(elements) do
    elements
    |> Enum.flat_map(&extract_text_from_element/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp extract_text_from_page(_), do: ""

  defp extract_text_from_element(%{"shape" => %{"text" => text}}),
    do: extract_text_runs(text)

  defp extract_text_from_element(%{"table" => table}), do: extract_table_text(table)

  defp extract_text_from_element(_), do: []

  defp extract_text_runs(%{"textElements" => elements}) when is_list(elements) do
    elements
    |> Enum.flat_map(fn
      %{"textRun" => %{"content" => content}} when is_binary(content) -> [content]
      _ -> []
    end)
  end

  defp extract_text_runs(_), do: []

  defp extract_table_text(%{"tableRows" => rows}) when is_list(rows) do
    Enum.flat_map(rows, fn
      %{"tableCells" => cells} when is_list(cells) ->
        Enum.flat_map(cells, fn
          %{"text" => text} -> extract_text_runs(text)
          _ -> []
        end)

      _ ->
        []
    end)
  end

  defp extract_table_text(_), do: []
end
