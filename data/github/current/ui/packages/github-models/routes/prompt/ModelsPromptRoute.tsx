import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type React from 'react'
import {useEffect, useMemo, useReducer} from 'react'
import {useLocation} from 'react-router-dom'
import type {GettingStartedPayload, ModelDetails, ShowModelPayload} from '../../types'
import {AzureModelClient} from '../../utils/azure-model-client'
import {getModelState} from '../../utils/model-state'
import {Evals} from './components/Evals'
import {Prompt} from './components/Prompt'
import {initialPromptEvalsState, PromptEvalsStateProvider} from './contexts/PromptEvalsStateContext'
import {PromptEvalsManager, PromptEvalsManagerContext, promptEvalsReducer} from './prompt-evals-manager'
import {ModelClientProvider} from '../playground/contexts/ModelClientContext'

export function ModelsPromptRoute() {
  const {model: catalogData, modelInputSchema, playgroundUrl, gettingStarted} = useRoutePayload<GettingStartedPayload>()

  const {promptFeedbackBannerDismissed} = useRoutePayload<ShowModelPayload>()
  const [promptEvalsState, promptEvalsDispatch] = useReducer(
    promptEvalsReducer,
    initialPromptEvalsState({
      promptFeedbackBannerDismissed,
    }),
  )
  const {model} = promptEvalsState
  const featureFlags = useFeatureFlags()

  // Make sure we only have one manager
  const manager = useMemo(
    () => new PromptEvalsManager(promptEvalsDispatch),
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

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catalogData.name]) // This prevents unnecessary re-renders by only running when the route-provided model updates

  const location = useLocation()
  const finalPathComponent = location.pathname.split('/').pop()?.toLowerCase()

  if (!featureFlags.github_models_prompt_evals && !featureFlags.github_models_prompt_editor) {
    return null
  }

  let content: React.ReactNode = null

  switch (finalPathComponent) {
    case 'prompt':
      content = <Prompt modelClient={modelClient} />
      break
    case 'evals':
      if (!featureFlags.github_models_prompt_evals) {
        return null
      }
      content = <Evals modelClient={modelClient} />
      break
  }

  return (
    <PromptEvalsStateProvider state={promptEvalsState}>
      <PromptEvalsManagerContext.Provider value={manager}>
        <ModelClientProvider modelClient={modelClient}>
          {model && (
            <div style={{height: 'calc(100dvh - 64px)'}} className="d-flex flex-column">
              {content}
            </div>
          )}
        </ModelClientProvider>
      </PromptEvalsManagerContext.Provider>
    </PromptEvalsStateProvider>
  )
}
