defmodule Oli.GoogleSlides.SlidesImport do
  @moduledoc """
  Orchestrates Google Slides import into an existing empty adaptive page.
  """

  require Logger

  alias Oli.Accounts.Author
  alias Oli.Authoring.Course
  alias Oli.Authoring.Editing.{ActivityEditor, PageEditor}
  alias Oli.Authoring.Editing.Utils, as: EditingUtils
  alias Oli.GoogleDocs.SlidesClient
  alias Oli.GoogleSlides.AdaptiveScreenBuilder
  alias Oli.GoogleSlides.Credentials
  alias Oli.GoogleSlides.MediaIngestor
  alias Oli.GoogleSlides.PresentationParser
  alias Oli.GoogleSlides.ScreenTitleGenerator
  alias Oli.GoogleSlides.Util
  alias Oli.GoogleSlides.Warnings
  alias Oli.ScopedFeatureFlags

  @guard_table :google_slides_import_guard
  @telemetry_event [:oli, :google_slides, :import]

  @spec import_available?(struct(), struct()) :: boolean()
  def import_available?(project, author) do
    ScopedFeatureFlags.enabled?(:google_slides_import, project) and
      Credentials.configured?(project.id) and
      EditingUtils.authorize_user(author, project) == {:ok}
  rescue
    _ -> false
  end

  @spec import(String.t(), String.t(), String.t(), Author.t(), keyword()) ::
          {:ok, map(), [map()]}
          | {:error, term(), [map()]}
  def import(project_slug, page_slug, presentation_url, author, opts \\ []) do
    warnings = []

    with {:ok, project} <- fetch_project(project_slug),
         true <- ScopedFeatureFlags.enabled?(:google_slides_import, project),
         {:ok} <- EditingUtils.authorize_user(author, project),
         true <- Credentials.configured?(project.id),
         guard_key = guard_key(project.slug, presentation_url),
         :ok <- acquire_guard(guard_key) do
      try do
        do_import(project, page_slug, presentation_url, author, opts)
      after
        release_guard(guard_key)
      end
    else
      false -> {:error, :feature_disabled, warnings}
      {:error, :import_in_progress} -> {:error, :import_in_progress, warnings}
      {:error, reason} -> {:error, reason, warnings}
    end
  end

  defp do_import(project, page_slug, presentation_url, author, opts) do
    metadata = %{project_slug: project.slug}

    :telemetry.span(@telemetry_event, metadata, fn ->
      case perform_import(project, page_slug, presentation_url, author, opts) do
        {:ok, result, _warnings} = ok ->
          {ok, Map.merge(metadata, %{status: :ok, screen_count: Map.get(result, :screen_count)})}

        {:error, reason, _warnings} = err ->
          {err, Map.merge(metadata, %{status: :error, reason: reason})}
      end
    end)
  end

  defp perform_import(project, page_slug, presentation_url, author, opts) do
    llm_fallback = Keyword.get(opts, :llm_fallback, true)
    title_override = Keyword.get(opts, :title)

    with {:ok, credentials} <- Credentials.get_credentials_map(project.id),
         {:ok, access_token} <- SlidesClient.fetch_access_token(credentials),
         {:ok, presentation_json} <-
           SlidesClient.fetch_presentation_json(presentation_url, access_token, credentials),
         {:ok, slides, parse_warnings} <-
           PresentationParser.parse(presentation_json, access_token: access_token),
         {:ok, screens, screen_warnings} <-
           build_screens(slides, presentation_json, project.slug, access_token, llm_fallback),
         {:ok, page_content} <- build_page_content(screens),
         {:ok, revision} <-
           persist_page(
             project.slug,
             page_slug,
             author,
             page_content,
             title_override,
             presentation_json
           ) do
      warnings = parse_warnings ++ screen_warnings

      {:ok,
       %{
         revision_slug: revision.slug,
         screen_count: length(screens),
         revision: revision
       }, warnings}
    else
      {:error, :not_configured} ->
        {:error, :service_account_not_configured,
         [Warnings.build(:service_account_not_configured)]}

      {:error, :invalid_presentation_url} ->
        {:error, :invalid_presentation_url, [Warnings.build(:invalid_presentation_url)]}

      {:error, :google_slides_api_disabled} ->
        {:error, :google_slides_api_disabled, [Warnings.build(:google_slides_api_disabled)]}

      {:error, :presentation_not_accessible} ->
        {:error, :presentation_not_accessible,
         [
           Warnings.build(:presentation_not_accessible, %{
             service_account_email: presentation_access_email(project.id)
           })
         ]}

      {:error, {:token_http_status, _, _}} ->
        {:error, :token_error, [Warnings.build(:token_error, %{reason: "authentication failed"})]}

      {:error, :lock_not_acquired} ->
        {:error, :lock_not_acquired, []}

      {:error, :not_found} ->
        {:error, :import_persist_failed,
         [
           Warnings.build(:slide_import_failed, %{
             slide_index: 0,
             reason: "could not save imported activities to the page"
           })
         ]}

      {:error, reason} ->
        {:error, reason, []}
    end
  end

  defp build_screens(slides, _presentation_json, project_slug, access_token, llm_fallback) do
    {title_map, title_warnings} = ScreenTitleGenerator.generate_all(slides)

    {screens, warnings} =
      Enum.reduce(slides, {[], title_warnings}, fn slide, {acc, warn} ->
        all_images = slide.images |> Enum.map(&Map.put(&1, :slide_index, slide.index))

        {:ok, media_urls, media_warnings} =
          MediaIngestor.ingest_images(all_images, project_slug, access_token)

        case AdaptiveScreenBuilder.build(slide, media_urls, llm_fallback: llm_fallback) do
          {:ok, content, slide_warnings} ->
            screen = %{
              title: Map.get(title_map, slide.index, ScreenTitleGenerator.heuristic_title(slide)),
              content: content
            }

            {[screen | acc], warn ++ media_warnings ++ slide_warnings}

          {:error, reason} ->
            {acc,
             warn ++
               [
                 Warnings.build(:slide_import_failed, %{
                   slide_index: slide.index,
                   reason: inspect(reason)
                 })
               ]}
        end
      end)

    {:ok, Enum.reverse(screens), warnings}
  end

  defp build_page_content(screens) do
    {:ok,
     %{
       "advancedDelivery" => true,
       "advancedAuthoring" => true,
       "displayApplicationChrome" => false,
       "custom" => %{
         "contentMode" => "expert",
         "defaultScreenHeight" => 540,
         "defaultScreenWidth" => 1200,
         "enableHistory" => true,
         "maxScore" => 0,
         "responsiveLayout" => true,
         "themeId" => "torus-default-light",
         "totalScore" => 0
       },
       "additionalStylesheets" => ["/css/delivery_adaptive_themes_default_light.css"],
       "model" => [
         %{
           "id" => Util.deck_group_id(),
           "type" => "group",
           "layout" => "deck",
           "children" => []
         }
       ],
       "screens" => screens
     }}
  end

  defp persist_page(
         project_slug,
         page_slug,
         author,
         page_content,
         title_override,
         presentation_json
       ) do
    screens = Map.get(page_content, "screens", [])
    content_without_screens = Map.delete(page_content, "screens")

    with {:ok, created_activities} <- create_activities(project_slug, author, screens),
         deck_children <- activity_references(created_activities),
         [group | rest] <- content_without_screens["model"],
         updated_group <- Map.put(group, "children", deck_children),
         final_content <-
           Map.put(content_without_screens, "model", [updated_group | rest]),
         title <- title_override || SlidesClient.get_presentation_title(presentation_json),
         {:acquired} <- PageEditor.acquire_lock(project_slug, page_slug, author.email),
         {:ok, revision} <-
           PageEditor.edit(project_slug, page_slug, author.email, %{
             "title" => title,
             "objectives" => %{"attached" => []},
             "content" => final_content,
             "releaseLock" => true
           }) do
      {:ok, revision}
    else
      {:lock_not_acquired, _} -> {:error, :lock_not_acquired}
      error -> error
    end
  end

  defp create_activities(project_slug, author, screens) do
    results =
      Enum.map(screens, fn %{title: title, content: content} ->
        ActivityEditor.create(
          project_slug,
          "oli_adaptive",
          author,
          content,
          [],
          "embedded",
          title
        )
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        activities =
          Enum.map(results, fn {:ok, {revision, _content}} ->
            %{resource_id: revision.resource_id, slug: revision.slug, title: revision.title}
          end)

        {:ok, activities}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp activity_references(activities) do
    Enum.map(activities, fn activity ->
      %{
        "type" => "activity-reference",
        "activitySlug" => activity.slug,
        "custom" => %{
          "sequenceId" => "aa_#{Util.new_id("seq")}",
          "sequenceName" => activity.title
        }
      }
    end)
  end

  defp fetch_project(slug) do
    case Course.get_project_by_slug(slug) do
      nil -> {:error, {:not_found, :project}}
      project -> {:ok, project}
    end
  end

  defp presentation_access_email(project_id) do
    Credentials.get_client_email(project_id) || "the configured Google service account"
  end

  defp guard_key(project_slug, url) do
    {:google_slides_import, project_slug, :crypto.hash(:sha256, url)}
  end

  defp acquire_guard(key) do
    ensure_guard_table()

    case :ets.lookup(@guard_table, key) do
      [] ->
        :ets.insert(@guard_table, {key, true})
        :ok

      _ ->
        {:error, :import_in_progress}
    end
  end

  defp release_guard(key) do
    :ets.delete(@guard_table, key)
    :ok
  end

  defp ensure_guard_table do
    case :ets.info(@guard_table) do
      :undefined ->
        :ets.new(@guard_table, [:named_table, :set, :public, read_concurrency: true])

      _ ->
        :ok
    end
  end
end
