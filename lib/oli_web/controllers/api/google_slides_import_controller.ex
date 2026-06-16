defmodule OliWeb.Api.GoogleSlidesImportController do
  use OliWeb, :controller

  alias Oli.Authoring.Course
  alias Oli.GoogleSlides.{Credentials, GenAI, SlidesImport}
  alias Oli.ScopedFeatureFlags

  action_fallback OliWeb.FallbackController

  @doc """
  Returns whether Google Slides import is available for the project.
  """
  def status(conn, %{"project" => project_slug}) do
    with {:ok, project} <- fetch_project(project_slug),
         true <- ScopedFeatureFlags.enabled?(:google_slides_import, project) do
      json(conn, %{
        enabled: true,
        service_account_configured: Credentials.configured?(project.id),
        genai_configured: GenAI.configured?(),
        client_email: Credentials.get_client_email(project.id)
      })
    else
      false ->
        json(conn, %{enabled: false, service_account_configured: false})

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "project not found"})
    end
  end

  @doc """
  Imports a public Google Slides presentation into an adaptive page.
  """
  def create(conn, %{
        "project" => project_slug,
        "resource" => page_slug,
        "presentation_url" => presentation_url
      }) do
    author = conn.assigns.current_author

    case SlidesImport.import(project_slug, page_slug, presentation_url, author) do
      {:ok, result, warnings} ->
        conn
        |> put_status(:ok)
        |> json(%{
          revision_slug: result.revision_slug,
          screen_count: result.screen_count,
          warnings: warnings
        })

      {:error, reason, warnings} ->
        conn
        |> put_status(error_status(reason))
        |> json(%{
          error: error_message(reason),
          code: error_code(reason),
          warnings: warnings
        })
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "presentation_url is required"})
  end

  defp fetch_project(slug) do
    case Course.get_project_by_slug(slug) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp error_status(:google_slides_api_disabled), do: :unprocessable_entity
  defp error_status(:service_account_not_configured), do: :unprocessable_entity
  defp error_status(:invalid_presentation_url), do: :bad_request
  defp error_status(:presentation_not_accessible), do: :forbidden
  defp error_status(:feature_disabled), do: :forbidden
  defp error_status(:import_persist_failed), do: :unprocessable_entity
  defp error_status(:lock_not_acquired), do: :conflict
  defp error_status(:import_in_progress), do: :conflict
  defp error_status({:not_authorized}), do: :forbidden
  defp error_status(_), do: :unprocessable_entity

  defp error_code(reason), do: reason

  defp error_message(:service_account_not_configured),
    do: "Google Slides import is not configured on this server."

  defp error_message(:invalid_presentation_url),
    do: "The Google Slides URL is invalid."

  defp error_message(:google_slides_api_disabled),
    do:
      "The Google Slides API is not enabled for the service account's Google Cloud project. Enable it in Google Cloud Console, then retry."

  defp error_message(:presentation_not_accessible),
    do:
      "Could not access the presentation. Share it with the configured Google service account as Viewer, or set sharing to Anyone with the link can view."

  defp error_message(:feature_disabled),
    do: "Google Slides import is not enabled for this project."

  defp error_message(:import_persist_failed),
    do: "Imported slides could not be saved to the page. Please try again."

  defp error_message(:lock_not_acquired),
    do: "This page is locked by another author. Try again after they finish editing."

  defp error_message(:import_in_progress),
    do: "An import is already in progress for this presentation."

  defp error_message({:not_authorized}), do: "Not authorized."

  defp error_message(reason), do: inspect(reason)
end
