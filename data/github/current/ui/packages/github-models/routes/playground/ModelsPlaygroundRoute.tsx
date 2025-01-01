import {testIdProps} from '@github-ui/test-id-props'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Playground} from './components/Playground'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {PlaygroundManagerContext, PlaygroundManager, tasksReducer, Panel} from '../../utils/playground-manager'
import {initialPlaygroundState, PlaygroundStateProvider} from '../../contexts/PlaygroundStateContext'
import {RAGContextProvider} from './contexts/RAGContext'
import React, {useReducer, useMemo, useEffect} from 'react'
import type {GettingStartedPayload, ModelDetails} from '../../types'
import {useSearchParams} from '@github-ui/use-navigate'
import {getModelStateFromPreset} from '../../utils/presets'
import {getModelStateDefaults} from '../../utils/model-state'
import {AzureModelClient} from '../../utils/azure-model-client'

export function ModelsPlaygroundRoute() {
  const {
    model,
    modelInputSchema,
    playgroundUrl,
    gettingStarted,
    comparedModelDetails,
    appliedPreset,
    miniplaygroundIcebreaker,
    canUseO1Models,
  } = useRoutePayload<GettingStartedPayload>()

  const [playgroundState, playgroundDispatch] = useReducer(tasksReducer, initialPlaygroundState())
  const {models = [], syncInputs = false} = playgroundState
  const featureFlags = useFeatureFlags()

  // Make sure we only have one manager
  const manager = useMemo(
    () => new PlaygroundManager(playgroundDispatch),
    [], // Do not add any dependencies here - the manager is designed to only exist once
  )
  const modelClient = useMemo(() => new AzureModelClient(playgroundUrl), [playgroundUrl])
  const modelDetails: ModelDetails = {catalogData: model, modelInputSchema, gettingStarted}
  const [searchParams] = useSearchParams()

  // If a preset is set or inputs are synced we want to retain params when switching models
  const keepParameters = searchParams.has('preset') || syncInputs

  useEffect(() => {
    // On the first run through we set the main model
    if (!models.length) {
      // If a preset is applied, we want to use the preset values instead of the defaults
      const initialModelState = appliedPreset
        ? getModelStateFromPreset(appliedPreset, modelDetails)
        : getModelStateDefaults(modelDetails)

      manager.setModelState(Panel.Main, initialModelState)
      manager.setPreferredLanguageFromLocalStorage(gettingStarted)

      // If there is an icebreaker we want to send the message immediately
      if (miniplaygroundIcebreaker) {
        const noAttachments = [] as string[]
        manager.sendMessage(Panel.Main, initialModelState, modelClient, miniplaygroundIcebreaker, noAttachments)
      }

      // Set up the side model if required
      if (comparedModelDetails) {
        // We always wants to sync the inputs initially
        manager.setSyncInputs(true)
        manager.setModelState(Panel.Side, getModelStateDefaults(comparedModelDetails))
      }
    }

    // We only want to update the main model if it's different from the model defined in the URL
    if (models[Panel.Main]?.catalogData.name !== model.name) {
      manager.updateMainModel(modelDetails, models, keepParameters)
    }

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [model.name]) // This prevents unnecessary re-renders by only running when the route-provided model updates
  const onComparisonMode = models.length > 1

  const FeatureFlaggedRAGContextProvider = useMemo(() => {
    return featureFlags.project_neutron_rag ? RAGContextProvider : React.Fragment
  }, [featureFlags.project_neutron_rag])

  return (
    <PlaygroundStateProvider state={playgroundState}>
      <PlaygroundManagerContext.Provider value={manager}>
        <FeatureFlaggedRAGContextProvider>
          <div {...testIdProps('playground')} className="d-flex height-full overflow-auto">
            {models.map((modelState, index) => (
              <Playground
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={`${modelState.catalogData.name}-${index}`}
                modelState={modelState}
                position={index}
                onComparisonMode={onComparisonMode}
                canUseO1Models={canUseO1Models}
                modelClient={modelClient}
              />
            ))}
          </div>
        </FeatureFlaggedRAGContextProvider>
      </PlaygroundManagerContext.Provider>
    </PlaygroundStateProvider>
  )
}
