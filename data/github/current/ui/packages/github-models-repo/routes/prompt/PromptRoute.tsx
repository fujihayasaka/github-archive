import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type React from 'react'
import {useMemo, useReducer, useState} from 'react'
import {useLocation} from 'react-router-dom'
import {useFilteredModels} from '../../hooks/use-filtered-models'
import {Compare} from './components/Compare'
import {Prompt} from './components/Prompt'
import {ModelsProvider} from './contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from './contexts/PromptCompareStateContext'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from './prompt-compare-manager'
import {isPromptComparePage, parsePrompt, type PromptConfig} from './prompts'
import type {PromptAppPayload} from './types'
import {PromptLayout} from './components/PromptLayout'
import {PromptFileHeader} from './components/PromptFileHeader'
import {PromptToolbar} from './components/PromptToolbar'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {PaidUsageBanner} from '@github-ui/github-models/PaidUsageBanner'

export function PromptRoute() {
  const {payload} = useAppPayload<PromptAppPayload>()
  const {inferenceUrl, promptPath, prompt, repository, restrictedModels, paidUsageBannerDismissed, businessSlug} =
    payload
  const [parsingError, setParsingError] = useState('')

  const prompts: PromptConfig[] = []
  try {
    const parsedPrompt = useMemo(() => parsePrompt(promptPath, prompt), [promptPath, prompt])
    prompts.push(parsedPrompt)
  } catch (e) {
    if (!parsingError) {
      setParsingError((e as Error).message)
    }
  }

  const modelClient = useMemo(() => new AzureModelClient(inferenceUrl), [inferenceUrl])

  const {availableModels, isLoadingModels} = useFilteredModels(repository.ownerLogin, repository.name, restrictedModels)

  // Determine what view we are rendering, Editor or Compare?
  const location = useLocation()
  const finalPathComponent = isPromptComparePage(location.pathname) ? 'compare' : 'prompt'
  const isNewPrompt = location.pathname.includes('models/prompt/new')
  const [promptCompareState, promptCompareDispatch] = useReducer(
    promptCompareReducer,
    initialPromptCompareState(prompts),
  )

  // Make sure we only have one manager
  const manager = useMemo(
    () => new PromptCompareManager(promptCompareDispatch),
    [], // Do not add any dependencies here - the manager is designed to only exist once
  )

  if (parsingError) {
    return (
      <CurrentRepositoryProvider repository={repository}>
        <PromptLayout>
          <PromptFileHeader prompt={{messages: [], path: promptPath}} isDirty={false} />
          <div className="border rounded-2 d-flex flex-column">
            <PromptToolbar disabled />
            <Blankslate>
              <Blankslate.Visual>
                <AlertIcon size="medium" className="fgColor-muted" />
              </Blankslate.Visual>
              <Blankslate.Heading>We could not load your prompt</Blankslate.Heading>
              <Blankslate.Description>
                Please check your prompt file for formatting.{' '}
                <Link
                  href="https://docs.github.com/github-models/use-github-models/storing-prompts-in-github-repositories"
                  inline
                >
                  Review the .yml file format.
                </Link>
                <br />
                <br />
                <span className="bgColor-attention-muted fgColor-attention">{parsingError}</span>
              </Blankslate.Description>
            </Blankslate>
          </div>
        </PromptLayout>
      </CurrentRepositoryProvider>
    )
  }

  if (isLoadingModels) {
    // For now, wait until we have the models available
    return null
  }

  let content: React.ReactNode = null

  switch (finalPathComponent) {
    default:
    case 'prompt':
      content = <Prompt modelClient={modelClient} isNewPrompt={isNewPrompt} />
      break
    case 'compare': {
      content = <Compare modelClient={modelClient} mode="compare" isNewPrompt={promptPath === ''} />
      break
    }
  }

  return (
    <CurrentRepositoryProvider repository={repository}>
      <ModelsProvider models={availableModels}>
        <PromptCompareStateProvider state={promptCompareState}>
          <PromptCompareManagerContext.Provider value={manager}>
            <PaidUsageBanner
              dismissed={paidUsageBannerDismissed}
              repository={repository}
              businessSlug={businessSlug}
              className="mt-3 mx-3"
            />
            <div className="d-flex flex-column">{content}</div>
          </PromptCompareManagerContext.Provider>
        </PromptCompareStateProvider>
      </ModelsProvider>
    </CurrentRepositoryProvider>
  )
}
