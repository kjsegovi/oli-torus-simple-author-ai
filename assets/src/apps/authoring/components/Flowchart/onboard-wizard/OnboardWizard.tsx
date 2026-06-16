import React, { useState } from 'react';
import { Button } from 'react-bootstrap';
import Spinner from 'react-bootstrap/Spinner';
import { ApplicationMode } from '../../../store/app/slice';
import { D6 } from './D6';
import { D20 } from './D20';
import { Landscape } from './Landscape';
import { LeftArrow } from './LeftArrow';
import { Portrait } from './Portrait';
import { RightArrow } from './RightArrow';

export type LessonSource = 'empty' | 'google_slides';

interface GoogleSlidesImportConfig {
  enabled: boolean;
  available: boolean;
}

interface Props {
  onSetupComplete: (mode: ApplicationMode, title: string) => void;
  onImportComplete?: (mode: ApplicationMode, title: string, presentationUrl: string) => void;
  startStep?: number;
  initialTitle?: string;
  presetMode?: ApplicationMode;
  googleSlidesImport?: GoogleSlidesImportConfig;
}

export const OnboardWizard: React.FC<Props> = ({
  startStep,
  onSetupComplete,
  onImportComplete,
  initialTitle,
  presetMode,
  googleSlidesImport,
}) => {
  const [step, setStep] = useState(startStep || 0);
  const [builderVersion, setBuilderVersion] = useState(
    presetMode === 'expert' ? 2 : presetMode === 'flowchart' ? 1 : 0,
  );
  const [lessonType, setLessonType] = useState(1);
  const [title, setTitle] = useState(initialTitle || '');
  const [lessonSource, setLessonSource] = useState<LessonSource>('empty');
  const [presentationUrl, setPresentationUrl] = useState('');
  const [importError, setImportError] = useState<string | null>(null);
  const compactAdvancedFlow = presetMode === 'expert';
  const canImportSlides = Boolean(
    googleSlidesImport?.enabled && googleSlidesImport?.available && onImportComplete,
  );

  const importUnavailableMessage = (() => {
    if (canImportSlides) {
      return null;
    }

    if (!googleSlidesImport?.enabled) {
      return 'Google Slides import is not enabled for this project. Enable the google_slides_import feature in project settings.';
    }

    return 'Google Slides import is not configured on this server yet. Contact your administrator.';
  })();

  const commitChanges = () => {
    setStep(workingStep());
    const mode =
      presetMode || (builderVersion === 1 ? ('flowchart' as const) : ('expert' as const));

    onSetupComplete(mode, title);
  };

  const commitImport = async () => {
    if (!onImportComplete) {
      return;
    }

    setImportError(null);
    setStep(workingStep());

    try {
      const mode =
        presetMode || (builderVersion === 1 ? ('flowchart' as const) : ('expert' as const));
      await onImportComplete(mode, title, presentationUrl);
    } catch (error: any) {
      const message =
        error?.error ||
        error?.message ||
        'Import failed. Check the URL and sharing settings.';
      setImportError(message);
      setStep(sourceStep());
    }
  };

  const workingStep = () => (compactAdvancedFlow ? 3 : 4);
  const sourceStep = () => (compactAdvancedFlow ? 1 : 3);

  const afterTitleNext = () => {
    if (compactAdvancedFlow) {
      setStep(sourceStep());
      return;
    }

    setStep(1);
  };

  const afterBuilderNext = () => {
    if (builderVersion === 2) {
      setStep(sourceStep());
      return;
    }

    setStep(2);
  };

  const afterSourceNext = () => {
    if (lessonSource === 'google_slides') {
      void commitImport();
      return;
    }

    commitChanges();
  };

  return (
    <div className="onboard-wizard">
      <div className="wizard-window">
        {step === 0 && (
          <Step1
            title={title}
            setTitle={setTitle}
            onNext={afterTitleNext}
            compactMode={compactAdvancedFlow}
          />
        )}
        {step === 1 && !compactAdvancedFlow && (
          <Step2
            selected={builderVersion}
            setSelected={setBuilderVersion}
            onNext={afterBuilderNext}
            onBack={() => setStep(0)}
          />
        )}

        {step === sourceStep() && (
          <StepSource
            selected={lessonSource}
            setSelected={setLessonSource}
            presentationUrl={presentationUrl}
            setPresentationUrl={setPresentationUrl}
            importError={importError}
            importAvailable={canImportSlides}
            importUnavailableMessage={importUnavailableMessage}
            onNext={afterSourceNext}
            onBack={() => setStep(compactAdvancedFlow ? 0 : builderVersion === 2 ? 1 : 2)}
            compactMode={compactAdvancedFlow}
          />
        )}

        {step === 2 && builderVersion === 1 && (
          <Step3
            selected={lessonType}
            setSelected={setLessonType}
            onNext={commitChanges}
            onBack={() => setStep(1)}
          />
        )}

        {(step === workingStep() || step === 3) && <Working compactMode={compactAdvancedFlow} />}
      </div>
    </div>
  );
};

const Working: React.FC<{ compactMode?: boolean }> = ({ compactMode = false }) => {
  return (
    <div className="wizard-content">
      <h1 className="wizard-header">
        {compactMode ? 'Opening in Edit Mode' : '3. Advanced Authoring'}
      </h1>
      <div className="wizard-body working">
        <Spinner animation="border" />
        <span>Working...</span>
      </div>
      <div className="wizard-footer">
        {!compactMode && (
          <div className="wizard-step">
            <div className="wizard-step">Step 3/3</div>
          </div>
        )}
      </div>
    </div>
  );
};

const StepSource: React.FC<{
  selected: LessonSource;
  setSelected: (value: LessonSource) => void;
  presentationUrl: string;
  setPresentationUrl: (value: string) => void;
  importError: string | null;
  importAvailable: boolean;
  importUnavailableMessage: string | null;
  onNext: () => void;
  onBack: () => void;
  compactMode?: boolean;
}> = ({
  selected,
  setSelected,
  presentationUrl,
  setPresentationUrl,
  importError,
  importAvailable,
  importUnavailableMessage,
  onNext,
  onBack,
  compactMode = false,
}) => {
  const canContinue =
    selected === 'empty' ||
    (selected === 'google_slides' && importAvailable && presentationUrl.trim().length > 0);

  return (
    <div className="wizard-content">
      <h1 className="wizard-header">
        {compactMode ? 'Choose a starting point' : 'Select a starting point'}
      </h1>
      <div className="wizard-body source-step">
        <div className="builder-version-options">
          <div
            className={`builder-version-option ${selected === 'empty' ? 'active' : ''}`}
            onClick={() => setSelected('empty')}
          >
            <label>Empty lesson</label>
            <p>Start with a blank Advanced Author lesson and add screens manually.</p>
          </div>
          <div
            className={`builder-version-option ${!importAvailable ? 'disabled' : ''} ${
              selected === 'google_slides' ? 'active' : ''
            }`}
            onClick={() => {
              if (importAvailable) {
                setSelected('google_slides');
              }
            }}
          >
            <label>Import Google Slides</label>
            <p>Create one screen per slide from a public Google Slides presentation.</p>
            {!importAvailable && importUnavailableMessage && (
              <p className="mt-2 mb-0">{importUnavailableMessage}</p>
            )}
          </div>
        </div>
        {selected === 'google_slides' && importAvailable && (
          <div className="wizard-url-field mt-3">
            <label className="wizard-url-label" htmlFor="google-slides-url">
              Google Slides URL
            </label>
            <input
              id="google-slides-url"
              value={presentationUrl}
              onChange={(e) => setPresentationUrl(e.target.value)}
              type="url"
              className="wizard-url-input"
              placeholder="https://docs.google.com/presentation/d/..."
            />
            <p className="wizard-url-help mt-2 mb-0">
              The presentation must be shared as <strong>Anyone with the link can view</strong>.
            </p>
            {importError && <p className="text-danger mt-2 mb-0">{importError}</p>}
          </div>
        )}
      </div>
      <div className="wizard-footer">
        {!compactMode && <div className="wizard-step">Step 3/3</div>}
        <div className="wizard-buttons">
          <Button onClick={onBack}>
            <LeftArrow stroke="#FFFFFF" />
            Back
          </Button>
          <Button disabled={!canContinue} onClick={onNext}>
            Next
            <RightArrow stroke={!canContinue ? '#737373' : '#FFFFFF'} />
          </Button>
        </div>
      </div>
    </div>
  );
};

const Step3Advanced: React.FC<{
  onNext: () => void;
  onBack: () => void;
}> = ({ onNext, onBack }) => {
  return (
    <div className="wizard-content">
      <h1 className="wizard-header">3. Advanced Authoring</h1>
      <div className="wizard-body advanced-author-step">
        <p>
          Recommended for users with experience using html code, json editing, css styling and
          building logic and users ready to take their lessons to the next level
        </p>
        <h2>Allows you to</h2>
        <ul>
          <li>Create multidimensional and extended lessons</li>
          <li>Build complex lesson logic and interactions</li>
          <li>Create advanced conditioning in pathing</li>
          <li>Set complex scoring rules</li>
        </ul>
        <h2>Note</h2>

        <p>
          Projects created in Advanced Authoring do not open in Simple Authoring. This requires
          creating a new lesson project.
        </p>
      </div>
      <div className="wizard-footer">
        <div className="wizard-step">Step 3/3</div>
        <div className="wizard-buttons">
          <Button onClick={onBack}>
            <LeftArrow stroke="#FFFFFF" />
            Back
          </Button>
          <Button onClick={onNext}>
            Next
            <RightArrow stroke="#FFFFFF" />
          </Button>
        </div>
      </div>
    </div>
  );
};

const Step3: React.FC<{
  onNext: () => void;
  onBack: () => void;
  selected: number;
  setSelected: (value: number) => void;
}> = ({ onNext, selected, onBack, setSelected }) => {
  return (
    <div className="wizard-content">
      <h1 className="wizard-header">3. Select lesson type</h1>
      <div className="wizard-body">
        <div className="builder-version-options">
          <div
            className={`builder-version-option ${selected === 1 ? 'active' : ''}`}
            onClick={() => setSelected(1)}
          >
            <div className="big-icon">
              <Landscape />
            </div>
            <label>Landscape</label>
            <p>
              Perfect if the lesson will be mostly viewed by students on chromebooks and tablets.
            </p>
          </div>
          <div className={`builder-version-option disabled`}>
            <div className="big-icon">
              <Portrait />
            </div>
            <label className="disabled">Portrait - Coming Soon</label>
            <p>It will work great if most of it will be displayed by students on mobile phones.</p>
          </div>
        </div>
      </div>
      <div className="wizard-footer">
        <div className="wizard-step">Step 3/3</div>
        <div className="wizard-buttons">
          <Button onClick={onBack}>
            <LeftArrow stroke="#FFFFFF" />
            Back
          </Button>
          <Button disabled={selected === 0} onClick={onNext}>
            Next
            <RightArrow stroke={selected === 0 ? '#737373' : '#FFFFFF'} />
          </Button>
        </div>
      </div>
    </div>
  );
};

const Step2: React.FC<{
  onNext: () => void;
  onBack: () => void;
  selected: number;
  setSelected: (value: number) => void;
}> = ({ onNext, selected, onBack, setSelected }) => {
  return (
    <div className="wizard-content">
      <h1 className="wizard-header">2. Select Builder Version</h1>
      <div className="wizard-body">
        <div className="builder-version-options">
          <div
            className={`builder-version-option ${selected === 1 ? 'active' : ''}`}
            onClick={() => setSelected(1)}
          >
            <div className="big-icon">
              <D6 />
            </div>
            <label>Simple authoring</label>
            <p>Easily build lessons using templates, simplified interactions, and conditioning.</p>
          </div>
          <div
            className={`builder-version-option ${selected === 2 ? 'active' : ''}`}
            onClick={() => setSelected(2)}
          >
            <div className="big-icon">
              <D20 />
            </div>
            <label>Advanced authoring</label>
            <p>Build complex lessons using extended logic rules and CSS editing.</p>
          </div>
        </div>
      </div>
      <div className="wizard-footer">
        <div className="wizard-step">Step 2/3</div>
        <div className="wizard-buttons">
          <Button onClick={onBack}>
            <LeftArrow stroke="#FFFFFF" />
            Back
          </Button>
          <Button disabled={selected === 0} onClick={onNext}>
            Next
            <RightArrow stroke={selected === 0 ? '#737373' : '#FFFFFF'} />
          </Button>
        </div>
      </div>
    </div>
  );
};

const Step1: React.FC<{
  title: string;
  setTitle: (title: string) => void;
  onNext: () => void;
  compactMode?: boolean;
}> = ({ title, setTitle, onNext, compactMode = false }) => {
  return (
    <div className="wizard-content">
      <h1 className="wizard-header">
        {compactMode ? 'Write a title for your lesson' : '1. Write a title for your lesson'}
      </h1>
      <div className="wizard-body step-1">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          type="text"
          className="title-input"
          placeholder="Add lesson title..."
        />
      </div>
      <div className="wizard-footer">
        {!compactMode && <div className="wizard-step">Step 1/3</div>}
        <div className="wizard-buttons">
          <Button disabled={title.length === 0} onClick={onNext}>
            Next
            <RightArrow stroke={title.length === 0 ? '#737373' : '#FFFFFF'} />
          </Button>
        </div>
      </div>
    </div>
  );
};
