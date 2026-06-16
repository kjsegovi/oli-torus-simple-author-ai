import { PageContent } from '../../../../../data/content/resource';
import { acquireLock } from '../../../../../data/persistence/lock';
import { edit } from '../../../../../data/persistence/resource';
import { importGoogleSlides } from '../../../../../data/persistence/googleSlidesImport';
import { cloneT } from '../../../../../utils/common';
import { ApplicationMode } from '../../../store/app/slice';
import { authoringEditorUrl } from '../../../utils/authoringEditorUrl';

const applyExpertDefaults = (content: PageContent, appMode: ApplicationMode): PageContent => {
  content.custom = {
    contentMode: appMode,
    defaultScreenHeight: 540,
    defaultScreenWidth: appMode === 'flowchart' ? 1200 : 1000,
    enableHistory: true,
    maxScore: 0,
    responsiveLayout: appMode === 'flowchart',
    themeId: 'torus-default-light',
    totalScore: 0,
  };

  content.additionalStylesheets = [
    appMode === 'flowchart'
      ? '/css/delivery_adaptive_themes_flowchart.css'
      : '/css/delivery_adaptive_themes_default_light.css',
  ];

  return content;
};

export const onboardWizardImportComplete = async (
  title: string,
  projectSlug: string,
  revisionSlug: string,
  appMode: ApplicationMode,
  pageContent: PageContent,
  presentationUrl: string,
) => {
  const content = cloneT(pageContent);
  applyExpertDefaults(content, appMode);

  const lock = await acquireLock(projectSlug, revisionSlug);
  if (lock.type !== 'acquired') {
    throw new Error('Could not acquire lock');
  }

  const saveResult = await edit(
    projectSlug,
    revisionSlug,
    {
      title,
      objectives: { attached: [] },
      content,
      releaseLock: true,
    },
    true,
  );

  if (saveResult.type !== 'success') {
    throw new Error('Could not save page');
  }

  const importResult = await importGoogleSlides(
    projectSlug,
    saveResult.revision_slug,
    presentationUrl,
  );

  window.location.assign(authoringEditorUrl(importResult.revision_slug));
};
