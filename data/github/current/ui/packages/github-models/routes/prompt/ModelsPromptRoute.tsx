import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useEffect, useMemo, useReducer} from 'react'
import type {GettingStartedPayload, ModelDetails, ShowModelPayload} from '../../types'
import {AzureModelClient} from '../../utils/azure-model-client'
import {getModelState} from '../../utils/model-state'
import {ModelClientProvider} from '../playground/contexts/ModelClientContext'
import {Prompt} from './components/Prompt'
import {initialPromptState, PromptStateProvider} from './contexts/PromptStateContext'
import {PromptManager, PromptManagerContext, promptReducer} from './prompt-manager'
import {useAvailableModels} from '../playground/hooks/use-query-models'

export function ModelsPromptRoute() {
  const {model: catalogData, modelInputSchema, playgroundUrl, gettingStarted} = useRoutePayload<GettingStartedPayload>()

  const {promptFeedbackBannerDismissed} = useRoutePayload<ShowModelPayload>()
  const [promptState, promptDispatch] = useReducer(
    promptReducer,
    initialPromptState({
      promptFeedbackBannerDismissed,
    }),
  )

  const {data, isLoading} = useAvailableModels()
  const {model} = promptState

  // Make sure we only have one manager
  const manager = useMemo(
    () => new PromptManager(promptDispatch),
    [], // Do not add any dependencies here - the manager is designed to only exist once
  )
  const modelClient = useMemo(() => new AzureModelClient(playgroundUrl), [playgroundUrl])
  const modelDetails: ModelDetails = {catalogData, modelInputSchema, gettingStarted}

  useEffect(() => {
    // On the first run through we set the main model
    if (!model) {
      // If a preset is applied, we want to use the preset values instead of the defaults
      const initialModelState = getModelState(modelDetails)
      manager.setModelState(initialModelState)
    }

    // We only want to update the main model if it's different from the model defined in the URL
    if (model?.catalogData.name !== catalogData.name) {
      const keepParameters = false
      manager.updateModel(modelDetails, model, keepParameters)
    }

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catalogData.name]) // This prevents unnecessary re-renders by only running when the route-provided model updates

  return (
    <PromptStateProvider state={promptState}>
      <PromptManagerContext.Provider value={manager}>
        <ModelClientProvider modelClient={modelClient}>
          {model && (
            <div style={{height: 'calc(100dvh - 64px)'}} className="d-flex flex-column">
              <Prompt modelClient={modelClient} availableModels={data} isLoadingModels={isLoading} />
            </div>
          )}
        </ModelClientProvider>
      </PromptManagerContext.Provider>
    </PromptStateProvider>
  )
}
