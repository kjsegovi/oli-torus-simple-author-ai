export const authoringEditorUrl = (revisionSlug: string): string => {
  const { pathname } = window.location;
  const curriculumMatch = pathname.match(/^(.*\/curriculum\/)[^/]+(\/edit)?$/);

  if (curriculumMatch) {
    return `${curriculumMatch[1]}${revisionSlug}/edit`;
  }

  const resourceMatch = pathname.match(/^(.*\/resource\/)[^/]+(\/edit)?$/);

  if (resourceMatch) {
    return `${resourceMatch[1]}${revisionSlug}/edit`;
  }

  return `./${revisionSlug}`;
};
