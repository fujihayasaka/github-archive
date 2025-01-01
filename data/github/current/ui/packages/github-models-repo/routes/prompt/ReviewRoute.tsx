import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import {useMemo, useReducer, useState} from 'react'
import {useFilteredModels} from '../../hooks/use-filtered-models'
import {Compare} from './components/Compare'
import {ModelsProvider} from './contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from './contexts/PromptCompareStateContext'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from './prompt-compare-manager'
import {parsePrompt, type PromptConfig} from './prompts'
import type {ReviewAppPayload} from './types'

export function ReviewRoute() {
  const {payload} = useAppPayload<ReviewAppPayload>()
  const {inferenceUrl, repository, restrictedModels, headPrompt, basePrompt} = payload

  const modelClient = useMemo(() => new AzureModelClient(inferenceUrl), [inferenceUrl])
  const {availableModels, isLoadingModels} = useFilteredModels(repository.ownerLogin, repository.name, restrictedModels)

  const [parsingError, setParsingError] = useState('')

  const prompts: PromptConfig[] = []

  try {
    const basePromptConfig = useMemo(
      () => parsePrompt(basePrompt.path, basePrompt.content),
      [basePrompt.path, basePrompt.content],
    )
    prompts.push(basePromptConfig)
  } catch (e) {
    if (!parsingError) {
      setParsingError((e as Error).message)
    }
  }

  try {
    const headPromptConfig = useMemo(
      () => parsePrompt(headPrompt.path, headPrompt.content),
      [headPrompt.path, headPrompt.content],
    )
    prompts.push(headPromptConfig)
  } catch (e) {
    if (!parsingError) {
      setParsingError((e as Error).message)
    }
  }

  const promptInfo = [basePrompt, headPrompt]

  const [promptCompareState, promptCompareDispatch] = useReducer(
    promptCompareReducer,
    initialPromptCompareState(prompts, {
      review: {
        promptInfo,
      },
    }),
  )

  // Make sure we only have one manager
  const manager = useMemo(
    () => new PromptCompareManager(promptCompareDispatch),
    [], // Do not add any dependencies here - the manager is designed to only exist once
  )

  if (parsingError) {
    return (
      <Blankslate>
        <Blankslate.Visual>
          <AlertIcon size="medium" className="fgColor-muted" />
        </Blankslate.Visual>
        <Blankslate.Heading>Error parsing prompt</Blankslate.Heading>
        <Blankslate.Description>{parsingError}</Blankslate.Description>
      </Blankslate>
    )
  }

  if (isLoadingModels) {
    // For now, wait until we have the models available
    return null
  }

  return (
    <CurrentRepositoryProvider repository={repository}>
      <ModelsProvider models={availableModels}>
        <PromptCompareStateProvider state={promptCompareState}>
          <PromptCompareManagerContext.Provider value={manager}>
            <div style={{height: '100vh'}} className="d-flex flex-column">
              <Compare modelClient={modelClient} mode="review" />
            </div>
          </PromptCompareManagerContext.Provider>
        </PromptCompareStateProvider>
      </ModelsProvider>
    </CurrentRepositoryProvider>
  )
}
