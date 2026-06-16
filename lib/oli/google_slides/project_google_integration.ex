defmodule Oli.GoogleSlides.ProjectGoogleIntegration do
  @moduledoc """
  Stores encrypted Google service account credentials scoped to a project.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Oli.Authoring.Course.Project

  schema "project_google_integrations" do
    field :client_email, :string
    field :encrypted_service_account_json, Oli.Encrypted.Binary

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:project_id, :client_email, :encrypted_service_account_json])
    |> validate_required([:project_id, :client_email, :encrypted_service_account_json])
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:project_id)
  end
end
