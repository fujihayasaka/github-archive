import {testIdProps} from '@github-ui/test-id-props'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Playground} from './components/Playground'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {PlaygroundManager, tasksReducer, Panel} from '../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../contexts/PlaygroundManagerContext'
import {initialPlaygroundState, PlaygroundStateProvider} from '../../contexts/PlaygroundStateContext'
import {RAGContextProvider} from './contexts/RAGContext'
import React, {useReducer, useMemo, useEffect} from 'react'
import {SidebarSelectionOptions, type GettingStartedPayload, type ModelDetails} from '../../types'
import {useSearchParams} from '@github-ui/use-navigate'
import {combineParamsWithModel, getModelState, getMostRecentUserMessage} from '../../utils/model-state'
import {useResponsiveValue} from '@primer/react'
import {AzureModelClient} from '../../utils/azure-model-client'
import {getDefaultUiState, setLocalStorageUiState} from '../../utils/playground-local-storage'
import {ModelClientProvider} from './contexts/ModelClientContext'
import {GiveFeedback} from '../../components/GiveFeedback'
import {textAndAttachmentsFromMessageContent} from '../../utils/message-content-helper'
import {supportImageWithoutText} from '../../utils/image-validation'

export function ModelsPlaygroundRoute() {
  const {
    model,
    modelInputSchema,
    playgroundUrl,
    gettingStarted,
    comparedModelDetails,
    appliedPreset,
    miniplaygroundIcebreaker,
  } = useRoutePayload<GettingStartedPayload>()
  const [playgroundState, playgroundDispatch] = useReducer(tasksReducer, initialPlaygroundState())
  const {models = [], syncInputs = false} = playgroundState
  const mainModelState = models[Panel.Main]
  const sideModelState = models[Panel.Side]
  const featureFlags = useFeatureFlags()
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean

  const manager = useMemo(() => new PlaygroundManager(playgroundDispatch), [playgroundDispatch])
  const modelClient = useMemo(() => new AzureModelClient(playgroundUrl), [playgroundUrl])
  const modelDetails: ModelDetails = {catalogData: model, modelInputSchema, gettingStarted}
  const [searchParams] = useSearchParams()

  /**
   * This effect is responsible for setting the main and side model states
   * No model changes should be made outside of this effect
   */
  useEffect(() => {
    const uiState = getDefaultUiState()
    /* No route model provided */
    if (!model) {
      if (mainModelState) manager.removeModel(Panel.Main)
      setLocalStorageUiState({
        ...uiState,
        sidebarTab: SidebarSelectionOptions.DETAILS,
      })
      return
    }

    /* Update the main model */
    if (!mainModelState) {
      /* This is the first time we're loading a model */
      const initialModelState = getModelState(modelDetails, appliedPreset)
      manager.setModelState(Panel.Main, initialModelState)
      if (miniplaygroundIcebreaker) {
        manager.sendMessage(Panel.Main, initialModelState, modelClient, miniplaygroundIcebreaker)
      }
    } else if (!comparedModelDetails && sideModelState) {
      const retain = Number(searchParams.get('retain'))
      if (retain === Panel.Side) {
        /* A side model is becoming the main model */
        manager.setModelState(Panel.Main, sideModelState)
      }
      manager.removeModel(Panel.Side)
      manager.setSyncInputs(false)
    } else if (mainModelState.catalogData.name !== model.name) {
      /* We're switching the main model */
      const keepParameters = searchParams.has('preset') || syncInputs
      const newModelState = combineParamsWithModel({
        modelDetails,
        systemPromptOverride: keepParameters ? mainModelState.systemPrompt : undefined,
        responseFormatOverride: keepParameters ? mainModelState.responseFormat : undefined,
        jsonSchemaOverride: keepParameters ? mainModelState.jsonSchema : undefined,
        parametersOverride: keepParameters ? mainModelState.parameters : undefined,
        chatInputOverride: mainModelState.chatInput,
      })
      manager.setModelState(Panel.Main, newModelState)
    }

    if (isMobile) {
      /* We don't support comparison view on mobile */
      if (sideModelState) manager.removeModel(Panel.Side)
      return
    }

    /* Update the side model */
    if (comparedModelDetails) {
      if (!sideModelState) {
        /* This is the first time we're loading a side model */

        // We don't allow json_schema response formats in comparison mode yet, so if that's set we need to switch it to text
        const newResponseFormat =
          mainModelState?.responseFormat === 'json_schema' ? 'text' : mainModelState?.responseFormat

        const newModelState = combineParamsWithModel({
          modelDetails: comparedModelDetails,
          systemPromptOverride: mainModelState?.systemPrompt,
          responseFormatOverride: newResponseFormat,
          parametersOverride: mainModelState?.parameters,
          chatInputOverride: mainModelState?.chatInput,
        })
        manager.setSyncInputs(true)
        manager.setModelState(Panel.Side, newModelState)
        if (searchParams.get('resend-user-prompt') && mainModelState) {
          const lastUserPrompt = getMostRecentUserMessage(mainModelState.messages)
          if (lastUserPrompt) {
            const {text, attachments} = textAndAttachmentsFromMessageContent(lastUserPrompt)
            if (text || (attachments.length > 0 && supportImageWithoutText(comparedModelDetails.catalogData.name))) {
              manager.sendMessage(Panel.Side, newModelState, modelClient, text, attachments)
            }
          }
        }

        // ensure the main model doesn't have json_schema response format either
        const newMainModelState = combineParamsWithModel({
          modelDetails,
          responseFormatOverride: newResponseFormat,
          chatInputOverride: mainModelState?.chatInput,
          messagesOverride: mainModelState?.messages,
        })
        manager.setModelState(Panel.Main, newMainModelState)
      } else if (sideModelState.catalogData.name !== comparedModelDetails.catalogData.name) {
        /* We're switching the side model */
        const newModelState = combineParamsWithModel({
          modelDetails: comparedModelDetails,
          systemPromptOverride: syncInputs ? sideModelState.systemPrompt : undefined,
          responseFormatOverride: syncInputs ? sideModelState.responseFormat : undefined,
          parametersOverride: syncInputs ? sideModelState.parameters : undefined,
          chatInputOverride: sideModelState.chatInput,
        })
        manager.setModelState(Panel.Side, newModelState)
      }
    }

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [model, comparedModelDetails, isMobile]) // Only run when the model or comparedModelDetails changes

  const FeatureFlaggedRAGContextProvider = useMemo(() => {
    return featureFlags.project_neutron_rag ? RAGContextProvider : React.Fragment
  }, [featureFlags.project_neutron_rag])

  if (model && !mainModelState) {
    // We're still loading the model so we don't want to render anything
    return null
  }

  const onComparisonMode = !!(comparedModelDetails && sideModelState && !isMobile)

  return (
    <PlaygroundStateProvider state={playgroundState}>
      <PlaygroundManagerProvider manager={manager}>
        <FeatureFlaggedRAGContextProvider>
          <ModelClientProvider modelClient={modelClient}>
            <div style={{height: 'calc(100dvh - 64px)'}} className="d-flex flex-column">
              {isMobile && <GiveFeedback playground={!!mainModelState} mobile />}
              <div
                {...testIdProps('playground')}
                className={`flex-1 d-flex overflow-auto gap-3 ${isMobile ? 'p-2' : 'p-3'}`}
              >
                <Playground modelState={mainModelState} position={Panel.Main} />
                {onComparisonMode && <Playground modelState={sideModelState} position={Panel.Side} />}
              </div>
            </div>
          </ModelClientProvider>
        </FeatureFlaggedRAGContextProvider>
      </PlaygroundManagerProvider>
    </PlaygroundStateProvider>
  )
}
