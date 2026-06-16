defmodule Oli.GoogleSlides.Credentials do
  @moduledoc """
  Context for Google Slides service account credentials.

  Credentials resolve in this order:

  1. Project-specific service account stored in the database (optional override)
  2. Global service account from `GOOGLE_SLIDES_SERVICE_ACCOUNT_JSON_B64` in the server environment
  """

  import Ecto.Query

  alias Oli.GoogleSlides.ProjectGoogleIntegration
  alias Oli.Repo

  @service_account_keys ~w(type project_id private_key_id private_key client_email client_id auth_uri token_uri auth_provider_x509_cert_url client_x509_cert_url)

  @spec configured?(integer()) :: boolean()
  def configured?(project_id) when is_integer(project_id) do
    project_configured?(project_id) or global_configured?()
  end

  @spec global_configured?() :: boolean()
  def global_configured? do
    global_fallback_credentials() != nil
  end

  @spec credential_source(integer()) :: :project | :global | nil
  def credential_source(project_id) when is_integer(project_id) do
    cond do
      project_configured?(project_id) -> :project
      global_configured?() -> :global
      true -> nil
    end
  end

  @spec get_client_email(integer()) :: String.t() | nil
  def get_client_email(project_id) do
    case Repo.get_by(ProjectGoogleIntegration, project_id: project_id) do
      %ProjectGoogleIntegration{client_email: email} ->
        email

      nil ->
        case global_fallback_credentials() do
          %{"client_email" => email} when is_binary(email) -> email
          _ -> nil
        end
    end
  end

  @spec get_credentials_map(integer()) :: {:ok, map()} | {:error, :not_configured}
  def get_credentials_map(project_id) do
    case Repo.get_by(ProjectGoogleIntegration, project_id: project_id) do
      nil ->
        case global_fallback_credentials() do
          nil -> {:error, :not_configured}
          credentials -> {:ok, credentials}
        end

      %ProjectGoogleIntegration{encrypted_service_account_json: encrypted} ->
        with {:ok, json} <- Jason.decode(encrypted),
             :ok <- validate_service_account(json) do
          {:ok, json}
        else
          _ -> {:error, :not_configured}
        end
    end
  end

  @spec upsert!(integer(), String.t()) :: ProjectGoogleIntegration.t()
  def upsert!(project_id, service_account_json) when is_binary(service_account_json) do
    with {:ok, decoded} <- Jason.decode(service_account_json),
         :ok <- validate_service_account(decoded) do
      attrs = %{
        project_id: project_id,
        client_email: decoded["client_email"],
        encrypted_service_account_json: service_account_json
      }

      case Repo.get_by(ProjectGoogleIntegration, project_id: project_id) do
        nil ->
          %ProjectGoogleIntegration{}
          |> ProjectGoogleIntegration.changeset(attrs)
          |> Repo.insert!()

        integration ->
          integration
          |> ProjectGoogleIntegration.changeset(attrs)
          |> Repo.update!()
      end
    else
      {:error, reason} -> raise ArgumentError, "invalid service account json: #{inspect(reason)}"
      reason -> raise ArgumentError, "invalid service account json: #{inspect(reason)}"
    end
  end

  @spec delete!(integer()) :: :ok
  def delete!(project_id) do
    case Repo.get_by(ProjectGoogleIntegration, project_id: project_id) do
      nil -> :ok
      integration -> Repo.delete!(integration)
    end

    :ok
  end

  defp project_configured?(project_id) do
    Repo.exists?(from i in ProjectGoogleIntegration, where: i.project_id == ^project_id)
  end

  defp validate_service_account(%{} = json) do
    missing =
      @service_account_keys
      |> Enum.reject(&Map.has_key?(json, &1))

    case missing do
      [] -> :ok
      keys -> {:error, {:missing_keys, keys}}
    end
  end

  defp validate_service_account(_), do: {:error, :invalid_shape}

  defp global_fallback_credentials do
    case System.get_env("GOOGLE_SLIDES_SERVICE_ACCOUNT_JSON_B64") do
      nil ->
        nil

      encoded ->
        case decode_service_account_payload(encoded) do
          {:ok, json} -> json
          :error -> nil
        end
    end
  end

  defp decode_service_account_payload(encoded) when is_binary(encoded) do
    normalized =
      encoded
      |> String.trim()
      |> String.trim_trailing("%")

    with {:ok, json_binary} <- Base.decode64(normalized),
         {:ok, json} <- Jason.decode(json_binary),
         :ok <- validate_service_account(json) do
      {:ok, json}
    else
      _ -> :error
    end
  end
end
