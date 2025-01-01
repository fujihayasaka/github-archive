import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import type {Model} from '@github-ui/marketplace-common'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type React from 'react'
import {useMemo, useReducer} from 'react'
import {useLocation} from 'react-router-dom'
import {userHasAccessToModel} from '../../utils/model-access'
import {Compare} from './components/Compare'
import {Prompt} from './components/Prompt'
import {ModelsProvider} from './contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from './contexts/PromptCompareStateContext'
import {useModelsQuery} from './hooks/use-models-query'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from './prompt-compare-manager'
import {parsePrompt, type PromptConfig} from './prompts'
import type {EvalsRow, PromptAppPayload} from './types'

// Eventually this should move to a server-side API. For now we'll determine the available models here,
// to keep this concern out of the other components
function modelAvailable(restrictedModels: string[], model: Model) {
  if (model.task !== 'chat-completion') {
    return false
  }

  if (!userHasAccessToModel(model.name, restrictedModels)) {
    return false
  }

  return true
}

export function PromptRoute() {
  const {payload} = useAppPayload<PromptAppPayload>()
  const {inferenceUrl, promptPath, prompt, repository, restrictedModels} = payload

  const prompts: PromptConfig[] = [parsePrompt(promptPath, prompt)]

  const modelClient = useMemo(() => new AzureModelClient(inferenceUrl), [inferenceUrl])

  // Prefetch available models. As a future optimization we might restrict this only to the models needed by the
  // reference prompts, but for now we just fetch all of them. In most cases this should be cached.
  const {data: models, isLoading: isLoadingModels} = useModelsQuery()
  const availableModels = models?.filter(m => modelAvailable(restrictedModels, m)) || []

  // Determine what view we are rendering, Editor or Compare?
  const location = useLocation()
  const finalPathComponent = location.pathname.includes('models/prompt/compare') ? 'compare' : 'prompt'

  // TOOD: CS: Eventually we might want to move this to its own route
  const isPRCompare = location.search.includes('compare=')

  let content: React.ReactNode = null

  switch (finalPathComponent) {
    default:
    case 'prompt':
      content = <Prompt modelClient={modelClient} />
      break
    case 'compare': {
      let mode: 'compare' | 'pr-compare' = 'compare'
      if (isPRCompare) {
        mode = 'pr-compare'
      }
      content = <Compare modelClient={modelClient} mode={mode} />
      break
    }
  }

  // TODO: CS: Revisit this view. Should this be an extra route instead?
  // if (isPRCompare) {
  //   prompts.push(parsePrompt(promptPath, headPrompt!))
  // }

  const [promptCompareState, promptCompareDispatch] = useReducer(
    promptCompareReducer,
    initialPromptCompareState(prompts, {
      // TODO: CS: Less conditional navigation logic here
      compare: prompts[0]?.testData
        ? {
            isRunning: false,
            result: {},
            evaluators: [], // TODO: CS: Also get from prompt config
            rows: prompts[0].testData.map(
              (x, i) =>
                ({
                  id: i.toString(),
                  ...x,
                }) as EvalsRow,
            ),
          }
        : {
            isRunning: false,
            rows: [],
            result: [],
            evaluators: [],
          }, // TODO: CS: Figure out how we can conditionally provide this override
    }),
  )

  // Make sure we only have one manager
  const manager = useMemo(
    () => new PromptCompareManager(promptCompareDispatch),
    [], // Do not add any dependencies here - the manager is designed to only exist once
  )

  if (isLoadingModels) {
    // For now, wait until we have the models available
    return null
  }

  return (
    <CurrentRepositoryProvider repository={repository}>
      <ModelsProvider models={availableModels}>
        <PromptCompareStateProvider state={promptCompareState}>
          <PromptCompareManagerContext.Provider value={manager}>
            <div style={{height: 'calc(100dvh - 104px)'}} className="d-flex flex-column">
              {content}
            </div>
          </PromptCompareManagerContext.Provider>
        </PromptCompareStateProvider>
      </ModelsProvider>
    </CurrentRepositoryProvider>
  )
}
