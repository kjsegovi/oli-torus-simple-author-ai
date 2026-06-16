defmodule Oli.GoogleSlides.Warnings do
  @moduledoc """
  Warning catalogue for the Google Slides import pipeline.
  """

  @type code ::
          :presentation_not_accessible
          | :google_slides_api_disabled
          | :service_account_not_configured
          | :invalid_presentation_url
          | :token_error
          | :unsupported_element
          | :notes_parse_error
          | :notes_llm_fallback_failed
          | :media_upload_failed
          | :component_build_failed
          | :screen_title_generation_failed
          | :slide_import_failed

  @catalogue %{
    google_slides_api_disabled: %{
      severity: :error,
      template:
        "The Google Slides API is not enabled for the service account's Google Cloud project. Enable it in Google Cloud Console, then retry."
    },
    presentation_not_accessible: %{
      severity: :error,
      template:
        "Could not access the presentation. Share it with %{service_account_email} as Viewer, or set sharing to Anyone with the link can view."
    },
    service_account_not_configured: %{
      severity: :error,
      template: "This project has no Google Slides service account configured."
    },
    invalid_presentation_url: %{
      severity: :error,
      template: "The Google Slides URL is invalid."
    },
    token_error: %{
      severity: :error,
      template: "Failed to authenticate with Google: %{reason}."
    },
    unsupported_element: %{
      severity: :warn,
      template: "Unsupported slide element on slide %{slide_index}: %{element_type}."
    },
    notes_parse_error: %{
      severity: :warn,
      template: "Could not parse structured notes on slide %{slide_index}: %{reason}."
    },
    notes_llm_fallback_failed: %{
      severity: :warn,
      template: "LLM could not interpret speaker notes on slide %{slide_index}."
    },
    media_upload_failed: %{
      severity: :warn,
      template: "Failed to upload image on slide %{slide_index}: %{reason}."
    },
    component_build_failed: %{
      severity: :warn,
      template: "Failed to build component on slide %{slide_index}: %{reason}."
    },
    screen_title_generation_failed: %{
      severity: :warn,
      template:
        "Could not generate an AI screen title for slide %{slide_index}; using a heuristic title."
    },
    slide_import_failed: %{
      severity: :error,
      template: "Failed to import slide %{slide_index}: %{reason}."
    }
  }

  @spec build(code(), map()) :: map()
  def build(code, metadata \\ %{}) do
    entry = Map.fetch!(@catalogue, code)

    %{
      code: code,
      severity: entry.severity,
      message: format(entry.template, metadata),
      metadata: metadata
    }
  end

  defp format(template, metadata) do
    Enum.reduce(metadata, template, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
