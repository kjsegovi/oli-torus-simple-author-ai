export interface GoogleSlidesImportStatus {
  enabled: boolean;
  service_account_configured: boolean;
  client_email?: string | null;
}

export interface GoogleSlidesImportResult {
  revision_slug: string;
  screen_count: number;
  warnings: Array<{ code: string; message: string; severity: string }>;
}

export interface GoogleSlidesImportError {
  error: string;
  code: string;
  warnings?: GoogleSlidesImportResult['warnings'];
}

export const fetchGoogleSlidesImportStatus = async (
  projectSlug: string,
): Promise<GoogleSlidesImportStatus> => {
  const response = await fetch(`/api/v1/project/${projectSlug}/google_slides_import/status`, {
    credentials: 'same-origin',
  });

  if (!response.ok) {
    return { enabled: false, service_account_configured: false };
  }

  return response.json();
};

export const importGoogleSlides = async (
  projectSlug: string,
  pageSlug: string,
  presentationUrl: string,
): Promise<GoogleSlidesImportResult> => {
  const response = await fetch(
    `/api/v1/project/${projectSlug}/resource/${pageSlug}/google_slides_import`,
    {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ presentation_url: presentationUrl }),
    },
  );

  let payload: GoogleSlidesImportError | GoogleSlidesImportResult;

  try {
    payload = await response.json();
  } catch {
    throw {
      error: `Import failed (${response.status}). Please try again.`,
      code: 'invalid_response',
    } as GoogleSlidesImportError;
  }

  if (!response.ok) {
    throw payload as GoogleSlidesImportError;
  }

  return payload as GoogleSlidesImportResult;
};
