defmodule Oli.Repo.Migrations.CreateProjectGoogleIntegrations do
  use Ecto.Migration

  def change do
    create table(:project_google_integrations) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :client_email, :string, null: false
      add :encrypted_service_account_json, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_google_integrations, [:project_id])
  end
end
