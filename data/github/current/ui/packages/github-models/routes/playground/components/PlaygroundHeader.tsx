import {useCallback, useState} from 'react'
import {IconButton, LinkButton, useResponsiveValue} from '@primer/react'
import {StackIcon, XIcon} from '@primer/octicons-react'
import type {GettingStarted, SidebarSelectionOptions} from '../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {modelPlaygroundPath, modelPromptPath} from '@github-ui/paths'
import {templateRepositoryNwo} from '../../../utils/playground-types'
import ModelSwitcher from './ModelSwitcher'
import GettingStartedDialog from './GettingStartedDialog/GettingStartedDialog'
import {Panel} from '../../../utils/playground-manager'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {GiveFeedback} from '../../../components/GiveFeedback'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {UseThisModelButton} from '../../../components/UseThisModelButton'
import {PresetsMenu} from './presets/PresetsMenu'

export function PlaygroundHeader({
  model,
  position,
  gettingStarted,
  uiState,
  setUiState,
  handleSetSidebarTab,
}: {
  model: Model
  position: number
  gettingStarted: GettingStarted
  uiState: ModelPersistentUIState
  setUiState: (uiState: ModelPersistentUIState) => void
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
}) {
  const openInCodespacesUrl = `/codespaces/new?template_repository=${templateRepositoryNwo}`
  const [isGettingStartedDialogOpen, setGettingStartedDialogOpen] = useState(false)

  const {models = []} = usePlaygroundState()
  const onComparisonMode = models.length > 1
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const featureFlags = useFeatureFlags()

  const onCloseModel = () => {
    if (position === Panel.Main) {
      // If we're removing the main model, we need to navigate to the new main model
      navigate({
        pathname: modelPlaygroundPath(models[Panel.Side]?.catalogData || model),
        search: `retain=${Panel.Side}`,
      })
    } else {
      // If we're removing the side model, we just remove the compare_to
      setSearchParams()
    }
  }

  const onModelSelect = useCallback(
    async (m: Model) => {
      searchParams.delete('resend-user-prompt')
      if (position === Panel.Side) {
        setSearchParams({
          compare_to: m.name,
        })
      } else {
        navigate({
          pathname: modelPlaygroundPath(m),
          search: searchParams.toString(),
        })
      }
    },
    [position, setSearchParams, navigate, searchParams],
  )

  const handleAddModel = async (m: Model) => {
    const modelName = m.name
    if (!modelName) return

    setSearchParams({
      compare_to: modelName,
    })
  }

  const defaultClasses = 'd-flex flex-row flex-justify-between flex-items-center gap-3'
  const comparisonClasses = 'p-2 border border-bottom-0 rounded-top-2'
  const individualClasses = isMobile ? 'pb-2' : 'pb-3'

  return (
    <div className={`${defaultClasses} ${onComparisonMode ? comparisonClasses : individualClasses}`}>
      <div className="d-flex flex-items-center gap-2">
        <ModelSwitcher
          model={model}
          onSelect={onModelSelect}
          onComparisonMode={onComparisonMode}
          handleSetSidebarTab={handleSetSidebarTab}
        />
        {!onComparisonMode && !isMobile && (
          <ModelSwitcher
            model={model}
            onSelect={handleAddModel}
            onComparisonMode={false}
            handleSetSidebarTab={handleSetSidebarTab}
            variant="compare_button"
          />
        )}
      </div>
      <div className="d-flex flex-items-center gap-2">
        {!onComparisonMode && (
          <>
            {!isMobile && <GiveFeedback playground />}
            {(featureFlags.github_models_prompt_evals || featureFlags.github_models_prompt_editor) && (
              <LinkButton
                className={isMobile ? 'px-2' : ''}
                aria-label="Prompt editor"
                leadingVisual={StackIcon}
                href={modelPromptPath(model)}
              >
                {isMobile ? undefined : 'Prompt editor'}
              </LinkButton>
            )}
            {!isMobile && <PresetsMenu />}
          </>
        )}

        <UseThisModelButton
          className={isMobile ? 'px-2' : ''}
          variant="primary"
          model={model}
          onClick={() => setGettingStartedDialogOpen(true)}
        />
        {onComparisonMode && <IconButton icon={XIcon} aria-label="Close model" onClick={onCloseModel} />}
        {isGettingStartedDialogOpen && (
          <GettingStartedDialog
            openInCodespaceUrl={openInCodespacesUrl}
            onClose={() => setGettingStartedDialogOpen(false)}
            showCodespacesSuggestion
            gettingStarted={gettingStarted}
            modelName={model.name}
            uiState={uiState}
            setUiState={setUiState}
          />
        )}
      </div>
    </div>
  )
}
