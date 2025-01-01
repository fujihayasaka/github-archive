import type {Model} from '@github-ui/marketplace-common'
import {modelPlaygroundPath, modelPromptPath} from '@github-ui/paths'
import {CommandButton, GlobalCommands} from '@github-ui/ui-commands'
import {useNavigate} from '@github-ui/use-navigate'
import {CommandPaletteIcon, PlayIcon, SquareFillIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import {useCallback, useRef, useState, type FormEvent} from 'react'
import {useLocation} from 'react-router-dom'
import {GiveFeedback} from '../../../components/GiveFeedback'
import {UseThisModelButton} from '../../../components/UseThisModelButton'
import type {GettingStarted, ModelInputSchema} from '../../../types'
import {templateRepositoryNwo} from '../../../utils/playground-types'
import GettingStartedDialog from '../../playground/components/GettingStartedDialog/GettingStartedDialog'
import ModelSwitcher from '../../playground/components/ModelSwitcher'
import style from './Header.module.css'
import type {RepoModel} from '../../../../github-models-repo/types'

export function Header({
  model,
  gettingStarted,
  running,
  canRun,
  run,
  stop,
  availableModels,
  isLoadingModels,
}: {
  model: Model
  modelInputSchema: ModelInputSchema
  gettingStarted: GettingStarted
  running: boolean
  /** Should run be enabled */
  canRun?: boolean
  run: () => void
  stop?(): void
  availableModels: Model[] | RepoModel[]
  isLoadingModels: boolean
}) {
  const openInCodespacesUrl = `/codespaces/new?template_repository=${templateRepositoryNwo}`
  const [isGettingStartedDialogOpen, setGettingStartedDialogOpen] = useState(false)
  const useThisModelRef = useRef(null)
  const navigate = useNavigate()

  const handleRun = useCallback(() => {
    run()
  }, [run])

  const handleStop = useCallback(
    (e?: FormEvent) => {
      e?.preventDefault()

      if (stop) {
        stop()
      }
    },
    [stop],
  )

  const location = useLocation()

  const onModelSelect = useCallback(
    async (m: Model) => {
      const finalPathComponent = location.pathname.split('/').pop()?.toLowerCase()

      switch (finalPathComponent) {
        case 'prompt':
          navigate({pathname: modelPromptPath(m)})
          break

        default:
          navigate({pathname: modelPlaygroundPath(m)})
      }
    },
    [navigate, location],
  )

  return (
    <div className={style.header}>
      <GlobalCommands commands={{'github:submit-form': handleRun}} />
      <div>
        <div className={style.headerWrapper}>
          <div className={style.modelSwitcherWrapper}>
            <ModelSwitcher
              model={model}
              onSelect={onModelSelect}
              handleSetSidebarTab={() => {}}
              availableModels={availableModels}
              isLoadingModels={isLoadingModels}
            />
          </div>
          <div className={style.headerContent}>
            <div className={style.giveFeedbackWrapper}>
              <GiveFeedback />
            </div>

            <>
              <span className={style.goToPlaygroundMobileButton}>
                <IconButton
                  icon={CommandPaletteIcon}
                  aria-label="Chat"
                  onClick={() => {
                    navigate({
                      pathname: modelPlaygroundPath(model),
                    })
                  }}
                />
              </span>
              <Button
                className={style.goToPlaygroundButton}
                leadingVisual={CommandPaletteIcon}
                onClick={() => {
                  navigate({
                    pathname: modelPlaygroundPath(model),
                  })
                }}
              >
                Playground
              </Button>
            </>

            <UseThisModelButton ref={useThisModelRef} model={model} onClick={() => setGettingStartedDialogOpen(true)} />
            {running ? (
              <Button leadingVisual={SquareFillIcon} variant="danger" onClick={handleStop}>
                Stop
              </Button>
            ) : (
              <CommandButton
                leadingVisual={PlayIcon}
                variant="primary"
                commandId="github:submit-form"
                disabled={canRun === false}
                showKeybindingHint
              >
                Run
              </CommandButton>
            )}

            {isGettingStartedDialogOpen && (
              <GettingStartedDialog
                returnFocusRef={useThisModelRef}
                openInCodespaceUrl={openInCodespacesUrl}
                onClose={() => setGettingStartedDialogOpen(false)}
                showCodespacesSuggestion
                gettingStarted={gettingStarted}
                modelName={model.name}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
