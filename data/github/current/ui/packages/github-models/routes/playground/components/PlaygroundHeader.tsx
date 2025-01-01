import type {Model} from '@github-ui/marketplace-common'
import {
  modelPlaygroundPath,
  modelPromptPath,
  repoModelPlaygroundPath,
  repoPromptNewPath,
  type Repository,
} from '@github-ui/paths'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {SidebarCollapseIcon, StackIcon, XIcon} from '@primer/octicons-react'
import {IconButton, LinkButton, useResponsiveValue} from '@primer/react'
import {useCallback, useRef, useState} from 'react'
import {GiveFeedback} from '../../../components/GiveFeedback'
import {UseThisModelButton} from '../../../components/UseThisModelButton'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import type {GettingStarted, SidebarSelectionOptions} from '../../../types'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'
import {Panel} from '../../../utils/playground-manager'
import {templateRepositoryNwo} from '../../../utils/playground-types'
import GettingStartedDialog from './GettingStartedDialog/GettingStartedDialog'
import ModelSwitcher from './ModelSwitcher'
import {PresetsMenu} from './presets/PresetsMenu'
import type {RepoModel} from '../../../../github-models-repo/types'

export function PlaygroundHeader({
  model,
  position,
  repository,
  gettingStarted,
  uiState,
  setUiState,
  handleSetSidebarTab,
  fileTreeExpanded,
  setFileTreeExpanded,
  availableModels,
  isLoadingModels,
}: {
  model: Model
  position: number
  repository?: Repository
  gettingStarted: GettingStarted
  uiState: ModelPersistentUIState
  setUiState: (uiState: ModelPersistentUIState) => void
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
  fileTreeExpanded?: boolean
  setFileTreeExpanded?: (expanded: boolean) => void
  availableModels: Model[] | RepoModel[]
  isLoadingModels: boolean
}) {
  const openInCodespacesUrl = `/codespaces/new?template_repository=${templateRepositoryNwo}`
  const [isGettingStartedDialogOpen, setGettingStartedDialogOpen] = useState(false)
  const useThisModelRef = useRef(null)
  const {models = []} = usePlaygroundState()
  const onComparisonMode = models.length > 1
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()

  const onCloseModel = () => {
    if (position === Panel.Main) {
      // If we're removing the main model, we need to navigate to the new main model
      navigate({
        pathname: repository
          ? repoModelPlaygroundPath(repository, models[Panel.Side]?.catalogData || model)
          : modelPlaygroundPath(models[Panel.Side]?.catalogData || model),
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
          pathname: repository ? repoModelPlaygroundPath(repository, m) : modelPlaygroundPath(m),
          search: searchParams.toString(),
        })
      }
    },
    [searchParams, position, setSearchParams, navigate, repository],
  )

  const handleAddModel = async (m: Model) => {
    const modelName = m.name
    if (!modelName) return

    setSearchParams({
      compare_to: modelName,
    })
  }

  const defaultClasses = 'd-flex flex-row flex-justify-between flex-items-center gap-3'
  const showPresets = !isMobile && !repository

  return (
    <div className={`${defaultClasses} ${isMobile ? 'pb-2' : 'pb-3'}`}>
      <div className="d-flex flex-items-center gap-2">
        {!fileTreeExpanded && repository && setFileTreeExpanded && (
          <IconButton
            onClick={() => setFileTreeExpanded(true)}
            aria-label="Expand menu"
            icon={SidebarCollapseIcon}
            variant="invisible"
          />
        )}
        <ModelSwitcher
          model={model}
          onSelect={onModelSelect}
          handleSetSidebarTab={handleSetSidebarTab}
          repository={repository}
          isLoadingModels={isLoadingModels}
          availableModels={availableModels}
        />
        {!onComparisonMode && !isMobile && (
          <ModelSwitcher
            model={model}
            onSelect={handleAddModel}
            handleSetSidebarTab={handleSetSidebarTab}
            variant="compare_button"
            repository={repository}
            isLoadingModels={isLoadingModels}
            availableModels={availableModels}
          />
        )}
      </div>
      <div className="d-flex flex-items-center gap-2">
        {!onComparisonMode && (
          <>
            {!isMobile && !repository && <GiveFeedback playground />}
            <LinkButton
              className={isMobile ? 'px-2' : ''}
              aria-label="Prompt editor"
              leadingVisual={StackIcon}
              href={repository ? repoPromptNewPath(repository) : modelPromptPath(model)}
            >
              {isMobile ? undefined : 'Prompt editor'}
            </LinkButton>
            {showPresets && <PresetsMenu />}
          </>
        )}

        <UseThisModelButton
          className={isMobile ? 'px-2' : ''}
          variant="primary"
          model={model}
          ref={useThisModelRef}
          onClick={() => setGettingStartedDialogOpen(true)}
        />
        {onComparisonMode && <IconButton icon={XIcon} aria-label="Close model" onClick={onCloseModel} />}
        {isGettingStartedDialogOpen && (
          <GettingStartedDialog
            openInCodespaceUrl={openInCodespacesUrl}
            onClose={() => setGettingStartedDialogOpen(false)}
            showCodespacesSuggestion={!repository}
            gettingStarted={gettingStarted}
            modelName={model.name}
            uiState={uiState}
            setUiState={setUiState}
            returnFocusRef={useThisModelRef}
          />
        )}
      </div>
    </div>
  )
}
