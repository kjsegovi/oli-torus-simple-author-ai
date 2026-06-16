defmodule OliWeb.Api.GoogleSlidesImportControllerTest do
  use OliWeb.ConnCase, async: true

  import Oli.Factory

  alias Oli.ScopedFeatureFlags

  setup [:author_conn, :create_project]

  test "status returns feature and service account flags", %{conn: conn, project: project, author: author} do
    {:ok, _} = ScopedFeatureFlags.enable_feature(:google_slides_import, project, author)

    conn = get(conn, ~p"/api/v1/project/#{project.slug}/google_slides_import/status")

    assert %{
             "enabled" => true,
             "service_account_configured" => service_account_configured,
             "genai_configured" => genai_configured
           } = json_response(conn, 200)

    assert is_boolean(service_account_configured)
    assert is_boolean(genai_configured)
  end
end
