defmodule Oli.GoogleSlides.GenAI do
  @moduledoc """
  Shared GenAI access for the Google Slides import pipeline.

  Model resolution order:

  1. `ServiceConfig` named `"google_slides_import"`
  2. Default seeded `ServiceConfig` named `"standard-no-backup"`
  3. First persisted OpenAI `RegisteredModel`
  4. Ephemeral model built from `OPENAI_API_KEY` in the environment
  """

  require Logger

  import Ecto.Query, warn: false

  alias Oli.GenAI.Completions
  alias Oli.GenAI.Completions.{Message, RegisteredModel, ServiceConfig}
  alias Oli.Repo

  @service_name "google_slides_import"
  @fallback_service_name "standard-no-backup"
  @default_openai_url "https://api.openai.com"
  @default_openai_model "gpt-4o-mini"

  @spec configured?() :: boolean()
  def configured? do
    case resolve_model() do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @spec resolve_model() :: {:ok, RegisteredModel.t()} | {:error, :not_configured}
  def resolve_model do
    with {:error, :not_configured} <- service_config_model(@service_name),
         {:error, :not_configured} <- service_config_model(@fallback_service_name),
         {:error, :not_configured} <- first_openai_model(),
         {:error, :not_configured} <- env_openai_model() do
      {:error, :not_configured}
    else
      {:ok, model} -> {:ok, model}
    end
  end

  @spec complete(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(prompt, opts \\ []) do
    with {:ok, model} <- resolve_model() do
      messages =
        case Keyword.get(opts, :system) do
          nil -> [Message.new(:user, prompt)]
          system -> [Message.new(:system, system), Message.new(:user, prompt)]
        end

      case Completions.generate(messages, [], model) do
        {:ok, %{content: content}} when is_binary(content) ->
          {:ok, content}

        other ->
          Logger.debug("Google Slides GenAI completion failed: #{inspect(other)}")
          {:error, other}
      end
    end
  end

  @spec strip_code_fence(String.t()) :: String.t()
  def strip_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/```\s*$/, "")
    |> String.trim()
  end

  defp service_config_model(name) do
    case Repo.get_by(ServiceConfig, name: name) |> Repo.preload(:primary_model) do
      %ServiceConfig{primary_model: %RegisteredModel{} = model} -> {:ok, model}
      _ -> {:error, :not_configured}
    end
  rescue
    _ -> {:error, :not_configured}
  end

  defp first_openai_model do
    case Repo.one(from(m in RegisteredModel, where: m.provider == ^:open_ai, limit: 1)) do
      %RegisteredModel{} = model -> {:ok, model}
      _ -> {:error, :not_configured}
    end
  rescue
    _ -> {:error, :not_configured}
  end

  defp env_openai_model do
    case System.get_env("OPENAI_API_KEY") |> blank_to_nil() do
      nil ->
        {:error, :not_configured}

      api_key ->
        {:ok,
         %RegisteredModel{
           name: "google-slides-import-env",
           provider: :open_ai,
           model: openai_model_name(),
           url_template: System.get_env("OPENAI_API_URL") || @default_openai_url,
           api_key: api_key,
           secondary_api_key: System.get_env("OPENAI_ORG_KEY"),
           timeout: env_integer("OPENAI_TIMEOUT", 8000),
           recv_timeout: env_integer("OPENAI_RECV_TIMEOUT", 60_000),
           pool_class: :slow
         }}
    end
  end

  defp openai_model_name do
    System.get_env("GOOGLE_SLIDES_IMPORT_OPENAI_MODEL") ||
      System.get_env("OPENAI_MODEL") ||
      @default_openai_model
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default
        end

      _ ->
        default
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      nil
    else
      trimmed
    end
  end

  defp blank_to_nil(_), do: nil
end
