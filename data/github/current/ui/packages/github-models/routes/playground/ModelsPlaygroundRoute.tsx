import {testIdProps} from '@github-ui/test-id-props'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Playground} from './components/Playground'
import {useFeatureFlags, type EnabledFeatures} from '@github-ui/react-core/use-feature-flag'
import {PlaygroundManager, tasksReducer, Panel} from '../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../contexts/PlaygroundManagerContext'
import {initialPlaygroundState, PlaygroundStateProvider} from '../../contexts/PlaygroundStateContext'
import {RAGContextProvider} from './contexts/RAGContext'
import React, {useReducer, useMemo, useEffect} from 'react'
import {
  SidebarSelectionOptions,
  type GettingStartedPayload,
  type ModelDetails,
  type ModelInputSchema,
} from '../../types'
import {useSearchParams} from '@github-ui/use-navigate'
import {combineParamsWithModel, getModelState, getMostRecentUserMessage} from '../../utils/model-state'
import {useResponsiveValue} from '@primer/react'
import {AzureModelClient} from '../../utils/azure-model-client'
import {getDefaultUiState, setLocalStorageUiState} from '../../utils/playground-local-storage'
import {ModelClientProvider} from './contexts/ModelClientContext'
import {GiveFeedback} from '../../components/GiveFeedback'
import {textAndAttachmentsFromMessageContent} from '../../utils/message-content-helper'
import {supportImageWithoutText} from '../../utils/image-validation'
import {clsx} from 'clsx'
import type {Repository} from '@github-ui/paths'
import {ModelLegalTerms} from '../../components/ModelLegalTerms'
import styles from './ModelsPlaygroundRoute.module.css'
import {SimpleLayout} from '../../components/SimpleLayout'
import type {Model} from '@github-ui/marketplace-common'
import type {RepoModel} from '../../../github-models-repo/types'
import {useAvailableModels} from './hooks/use-query-models'

export const noOp = () => {}

export function ModelsPlaygroundRoute() {
  const {data, isLoading} = useAvailableModels()
  return (
    <SimpleLayout>
      <ModelsPlaygroundComponent availableModels={data} isLoadingModels={isLoading} />
    </SimpleLayout>
  )
}

/**
 * Strips the chat history parameter from the model input schema if the feature flag is enabled.
 * This is currently causing issues with OpenAI 4.1 models, and should be removed when the schema
 * issue is resolved.
 */
function stripChatHistoryFromModelInputSchema(featureFlags: EnabledFeatures, modelInputSchema: ModelInputSchema) {
  if (!featureFlags.models_playground_disable_chat_history_param) {
    return modelInputSchema
  }

  if ((modelInputSchema?.parameters || [])?.find(({key}) => key === 'chatHistory')) {
    // Remove chatHistory from the model input schema if it exists
    return {
      ...modelInputSchema,
      parameters: modelInputSchema?.parameters?.filter(({key}) => key !== 'chatHistory'),
    }
  }
  return modelInputSchema
}

export function ModelsPlaygroundComponent({
  availableModels,
  isLoadingModels,
  repository = undefined,
  fileTreeExpanded = true,
  setFileTreeExpanded = noOp,
}: {
  availableModels: Model[] | RepoModel[]
  isLoadingModels: boolean
  repository?: Repository
  fileTreeExpanded?: boolean
  setFileTreeExpanded?: (expanded: boolean) => void
}) {
  const {
    model,
    modelInputSchema: initialModelInputSchema,
    playgroundUrl = '',
    gettingStarted,
    comparedModelDetails: initialComparedModelDetails,
    appliedPreset,
    miniplaygroundIcebreaker,
  } = useRoutePayload<Partial<GettingStartedPayload>>() ?? {}

  const [playgroundState, playgroundDispatch] = useReducer(tasksReducer, initialPlaygroundState())
  const {models = [], syncInputs = false} = playgroundState
  const mainModelState = models[Panel.Main]
  const sideModelState = models[Panel.Side]
  const featureFlags = useFeatureFlags()
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean

  const modelInputSchema = stripChatHistoryFromModelInputSchema(featureFlags, initialModelInputSchema)
  const comparedModelDetails = initialComparedModelDetails
    ? {
        ...initialComparedModelDetails,
        modelInputSchema: stripChatHistoryFromModelInputSchema(
          featureFlags,
          initialComparedModelDetails?.modelInputSchema,
        ),
      }
    : undefined

  const manager = useMemo(() => new PlaygroundManager(playgroundDispatch), [playgroundDispatch])
  const modelClient = useMemo(() => new AzureModelClient(playgroundUrl), [playgroundUrl])
  const [searchParams] = useSearchParams()

  /**
   * This effect is responsible for setting the main and side model states
   * No model changes should be made outside of this effect
   */
  useEffect(() => {
    const uiState = getDefaultUiState()
    /* No route model provided */
    if (!model || !modelInputSchema || !gettingStarted) {
      if (mainModelState) manager.removeModel(Panel.Main)
      setLocalStorageUiState({
        ...uiState,
        sidebarTab: SidebarSelectionOptions.DETAILS,
      })
      return
    }

    const modelDetails: ModelDetails = {catalogData: model, modelInputSchema, gettingStarted}

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
          systemPromptOverride: mainModelState?.systemPrompt,
          responseFormatOverride: newResponseFormat,
          parametersOverride: mainModelState?.parameters,
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

    // eslint-disable-next-line react-hooks/react-compiler
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
            <div className={styles.playgroundPanel}>
              {isMobile && !repository && <GiveFeedback playground={!!mainModelState} mobile />}
              <div {...testIdProps('playground')} className={clsx(styles.playgroundContainer, 'flex-1 d-flex gap-3')}>
                <Playground
                  modelState={mainModelState}
                  position={Panel.Main}
                  repository={repository}
                  fileTreeExpanded={fileTreeExpanded}
                  setFileTreeExpanded={setFileTreeExpanded}
                  availableModels={availableModels}
                  isLoadingModels={isLoadingModels}
                />
                {onComparisonMode && (
                  <Playground
                    modelState={sideModelState}
                    position={Panel.Side}
                    repository={repository}
                    availableModels={availableModels}
                    isLoadingModels={isLoadingModels}
                  />
                )}
              </div>
              {onComparisonMode && (
                <div className="pt-3 pb-2 d-flex flex-justify-center pr-3">
                  <ModelLegalTerms modelName={mainModelState?.catalogData.name ?? sideModelState.catalogData.name} />
                </div>
              )}
            </div>
          </ModelClientProvider>
        </FeatureFlaggedRAGContextProvider>
      </PlaygroundManagerProvider>
    </PlaygroundStateProvider>
  )
}
