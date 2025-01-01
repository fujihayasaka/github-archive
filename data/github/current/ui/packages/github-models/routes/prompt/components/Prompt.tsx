import {PlaygroundChatMessageHeader} from '../../playground/components/PlaygroundChatMessageHeader'
import {useUser} from '@github-ui/use-user'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {StackIcon, TrashIcon} from '@primer/octicons-react'
import {Button, IconButton, PageLayout, Spinner, useResponsiveValue} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {useCallback, useEffect, useRef, useState} from 'react'
import {GiveFeedback} from '../../../components/GiveFeedback'
import type {EvalsRow, IndexModelsPayload, MessagePair, ModelInputChangeParams, ShowModelPayload} from '../../../types'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import {validateAndFilterParameters} from '../../../utils/model-state'
import {Panel} from '../../../utils/playground-manager'
import {getPromptEvalsLocalStorage} from '../../../utils/prompt-evals-local-storage'
import {PlaygroundChatMessage} from '../../playground/components/PlaygroundChatMessage'
import {usePromptEvalsState} from '../contexts/PromptEvalsStateContext'
import {referencedVariables, replaceVars} from '../evals-sdk/variables'
import {useExtractedPrompt} from '../hooks/use-extracted-prompt'
import {Header} from './Header'
import ParameterSettingsMenu from './ParameterSettingsMenu'
import styles from './Prompt.module.css'
import {PromptFeedbackBanner} from './PromptFeedbackBanner'
import {VariablesDialog} from './VariablesDialog'
import {ViewSwitcher} from './ViewSwitcher'
import {PromptAutocompleteInput} from './PromptAutocompleteInput'
import {usePromptEvalsManager} from '../prompt-evals-manager'
import {testIdProps} from '@github-ui/test-id-props'
import {PromptMessagePair} from './PromptMessagePair'
import type {PromptEvalsState} from '../prompt-evals-state'

export type PromptProps = {
  modelClient: AzureModelClient
}

export function Prompt({modelClient}: PromptProps) {
  const {prompt, systemPrompt, variables, evals, model, promptFeedbackBannerDismissed, messagePairs} =
    usePromptEvalsState()
  const {gettingStarted, modelInputSchema, catalogData, messages, isLoading} = model
  const lastIndex = messages.length - 1
  const manager = usePromptEvalsManager()
  const localStorage = getPromptEvalsLocalStorage()
  const isMobile = useResponsiveValue({narrow: true}, false)

  const {currentUser} = useUser()

  const modelStateWithParameters = localStorage?.parameters ? {...model, parameters: localStorage.parameters} : model

  const {promptExtractionModel} = useRoutePayload<ShowModelPayload>()

  const messagePairFlagEnabled = useFeatureFlag('github_models_prompt_message_pair')

  const referencedVariablesInState = ({
    prompt: updatedPrompt,
    systemPrompt: updatedSystemPrompt,
    messagePairs: updatedMessagePairs,
  }: Partial<PromptEvalsState>): string[] => {
    let variablesList: string[] = []
    if (updatedPrompt) variablesList = variablesList.concat(referencedVariables(updatedPrompt))
    if (updatedSystemPrompt) variablesList = variablesList.concat(referencedVariables(updatedSystemPrompt))
    if (updatedMessagePairs) {
      for (const pair of updatedMessagePairs) {
        variablesList = variablesList.concat(referencedVariables(pair.user))
        variablesList = variablesList.concat(referencedVariables(pair.assistant))
      }
    }

    const uniqueVariables = new Set(variablesList)
    return Array.from(uniqueVariables)
  }

  const [variableKeys, setVariableKeys] = useState<string[]>(() => {
    if (!prompt) return []
    return referencedVariablesInState({prompt, systemPrompt})
  })

  const messagesContainerRef = useRef<HTMLDivElement>(null)

  const scrollToBottom = useCallback(() => {
    messagesContainerRef.current?.scrollIntoView(false)
  }, [])

  useEffect(() => {
    requestAnimationFrame(scrollToBottom)
  }, [messages, scrollToBottom])

  // New handlers for the PromptAutocompleteInput component
  const handleManagerPromptInput = useCallback(
    (promptInput: string) => {
      manager.setPromptInput(promptInput)
      setVariableKeys(referencedVariablesInState({prompt: promptInput, systemPrompt, messagePairs}))
    },
    [manager, messagePairs, systemPrompt],
  )

  const handleManagerSystemPrompt = useCallback(
    (newPrompt: string) => {
      manager.setSystemPrompt(newPrompt)
      setVariableKeys(referencedVariablesInState({systemPrompt: newPrompt, prompt, messagePairs}))
    },
    [manager, messagePairs, prompt],
  )

  const handleManagerMessagePairs = useCallback(
    (messagePairInput: MessagePair[]) => {
      manager.setMessagePairs(messagePairInput)
      setVariableKeys(referencedVariablesInState({messagePairs: messagePairInput, prompt, systemPrompt}))
    },
    [manager, prompt, systemPrompt],
  )

  const handleModelParamsChange = ({key, value, validate}: ModelInputChangeParams) => {
    const unvalidatedParams = {
      ...modelStateWithParameters.parameters,
      [key]: value,
    }

    const params = validate
      ? validateAndFilterParameters(modelInputSchema?.parameters || [], unvalidatedParams)
      : unvalidatedParams

    manager.setParameters(params)
    manager.setParametersHasChanges(true)
  }

  const handleRun = useCallback(
    (vars: Record<string, string>) => {
      const variablesWithoutValue = variableKeys.filter(v => !vars[v])
      if (variablesWithoutValue.length > 0) {
        // One of the referenced variables doesn't have a value, ask the user for a value first
        setRequiredVariables(new Set(variablesWithoutValue))
        setShowRunVariablesDialog(true)
        return
      }

      // If this is a new variables combination, add as a data row
      if (!evals.rows.find(d => Object.keys(vars).every(v => d[v] === vars[v]))) {
        manager.evalsAddRow({
          id: evals.rows.length + 1,
          ...vars,
        } as EvalsRow)
      }

      const expandedPrompt = replaceVars(prompt, vars)
      const expandedSystemPrompt = systemPrompt ? replaceVars(systemPrompt, vars) : systemPrompt

      if (messagePairFlagEnabled && messagePairs) {
        const expandedMessagePairs = messagePairs.map(pair => ({
          assistant: replaceVars(pair.assistant, vars),
          user: replaceVars(pair.user, vars),
        }))
        manager.sendMessage(model, modelClient, expandedSystemPrompt, expandedPrompt, [], expandedMessagePairs)
      } else {
        manager.sendMessage(model, modelClient, expandedSystemPrompt, expandedPrompt)
      }
    },
    [variableKeys, evals.rows, prompt, systemPrompt, messagePairFlagEnabled, messagePairs, manager, model, modelClient],
  )

  const handleStop = useCallback(() => {
    modelClient.stopStreamingMessages(Panel.Main)
  }, [modelClient])

  const {promptExtractionCodeSnippet} = useRoutePayload<IndexModelsPayload>()
  const handleExtractedPrompt = useCallback(
    (extractedPrompt: string) => {
      manager.setPromptInput(extractedPrompt)
      manager.sendMessage(model, modelClient, systemPrompt, extractedPrompt)
    },
    [manager, modelClient, model, systemPrompt],
  )
  const {extractingPrompt} = useExtractedPrompt(
    promptExtractionModel || model.catalogData,
    modelClient,
    handleExtractedPrompt,
    promptExtractionCodeSnippet,
  )

  const [showEditVariablesDialog, setShowVariablesDialog] = useState(false)
  const handleCloseEditVariablesDialog = useCallback(
    (v?: Record<string, string>) => {
      if (v) {
        manager.setVariables(v)
      }
      setShowVariablesDialog(false)
    },
    [manager],
  )

  const [showRunVariablesDialog, setShowRunVariablesDialog] = useState(false)
  const handleCloseRunVariablesDialog = useCallback(
    (v?: Record<string, string>) => {
      setShowRunVariablesDialog(false)

      if (v) {
        // Persist variables
        manager.setVariables(v)

        // Reset required variables
        setRequiredVariables(undefined)

        handleRun(v)
      }
    },
    [manager, handleRun],
  )

  const [requiredVariables, setRequiredVariables] = useState<Set<string> | undefined>(undefined)

  const handleClearHistory = useCallback(() => {
    modelClient.stopStreamingMessages(Panel.Main)
    manager.evalsClearUserSystemPromptAndVariables()
    manager.resetHistory()
  }, [manager, modelClient])

  const blankSlate = (
    <div className={styles.blankSlate}>
      <Blankslate>
        <Blankslate.Visual>
          {extractingPrompt ? <Spinner size="medium" /> : <StackIcon size="medium" />}
        </Blankslate.Visual>
        <Blankslate.Heading>Iterate on your prompt</Blankslate.Heading>
        <Blankslate.Description>
          {extractingPrompt ? (
            'Extracting the prompt from your code...'
          ) : (
            <>
              Use the prompt editor to run a single prompt repeatedly, refining it and adjusting{' '}
              <code>{'{{variables}}'}</code> to achieve the perfect response.
            </>
          )}
        </Blankslate.Description>
      </Blankslate>
    </div>
  )

  return (
    <div className={styles.promptContainer}>
      {showEditVariablesDialog && (
        <VariablesDialog
          primaryTitle="Save"
          variables={variables}
          availableVariables={variableKeys}
          onClose={handleCloseEditVariablesDialog}
        />
      )}

      {showRunVariablesDialog && (
        <VariablesDialog
          primaryTitle="Run"
          variables={variables}
          availableVariables={variableKeys}
          requiredVariables={requiredVariables}
          onClose={handleCloseRunVariablesDialog}
        />
      )}

      <div className={styles.mobileHeader}>
        <GiveFeedback mobile />
      </div>
      <div className={styles.promptWrapper}>
        <div className={styles.responsiveWrapper}>
          <div className={styles.responsiveContainer}>
            <Header
              run={() => handleRun(variables)}
              stop={handleStop}
              running={isLoading}
              canRun={!!prompt}
              model={catalogData}
              modelInputSchema={modelInputSchema}
              gettingStarted={gettingStarted}
            />
            <div className="border overflow-hidden rounded-2 flex-grow-1 height-full">
              <div className="d-flex position-sticky top-0 p-2 border-bottom bgColor-muted flex-items-center">
                {useFeatureFlag('github_models_prompt_evals') && (
                  <>
                    <ViewSwitcher model={catalogData} />
                    <div
                      style={{width: '1px', height: '20px', margin: '0 8px', background: 'var(--borderColor-default'}}
                    />
                  </>
                )}
                <Button
                  size="small"
                  className="mr-2"
                  onClick={() => setShowVariablesDialog(true)}
                  disabled={variableKeys.length === 0}
                  {...testIdProps('edit-variables')}
                >
                  Edit <span>{isMobile ? 'vars' : 'variables'}</span>
                </Button>
                <ParameterSettingsMenu model={model} handleModelParamsChange={handleModelParamsChange} />
                <div className="flex-1" />
                <IconButton
                  icon={TrashIcon}
                  size="small"
                  aria-label="Clear prompts, variables, and chat"
                  className="ml-2"
                  disabled={!systemPrompt && !prompt}
                  onClick={handleClearHistory}
                  {...testIdProps('clear-prompt')}
                />
              </div>
              <PageLayout padding="none" containerWidth="full" columnGap="none" className={styles.promptLayout}>
                <PageLayout.Pane
                  aria-label="System and user prompts"
                  resizable
                  position={{narrow: 'end', regular: 'start', wide: 'start'}}
                  divider="none"
                  padding="none"
                >
                  <div className={styles.promptPane}>
                    <form>
                      <div className="mb-3" {...testIdProps('system-autocomplete-component')}>
                        <PromptAutocompleteInput
                          label="System"
                          prompt={systemPrompt ?? ''}
                          setPromptInput={handleManagerSystemPrompt}
                          variableKeys={variableKeys}
                          textareaPlaceholder="Define the model's behavior or role. Example: 'You are a spaceship captain telling intergalactic tales.'"
                          showImprovePrompt
                        />
                      </div>

                      <div className="mb-3" {...testIdProps('prompt-autocomplete-component')}>
                        <PromptAutocompleteInput
                          label="User"
                          prompt={prompt}
                          setPromptInput={handleManagerPromptInput}
                          variableKeys={variableKeys}
                          textareaPlaceholder="Enter the task or question for the model. Example: 'Write me a song about GitHub.' Use {{variable}} for placeholders."
                        />
                      </div>

                      {messagePairFlagEnabled && (
                        <PromptMessagePair
                          messagePairs={messagePairs ?? []}
                          setMessagePairs={handleManagerMessagePairs}
                          variableKeys={variableKeys}
                        />
                      )}
                    </form>
                  </div>
                </PageLayout.Pane>
                <PageLayout.Content as="div" className={styles.promptBody}>
                  <div className="height-full d-flex flex-column">
                    {!promptFeedbackBannerDismissed && (
                      <PromptFeedbackBanner onDismiss={() => manager.dismissPromptFeedbackBanner()} />
                    )}

                    {messages?.length > 0 ? (
                      <div className="p-3 overflow-auto flex-1" ref={messagesContainerRef}>
                        {messages.map((message, index) => (
                          // eslint-disable-next-line @eslint-react/no-array-index-key
                          <div key={`${message.role}-${index}`}>
                            <PlaygroundChatMessageHeader
                              message={message}
                              model={model.catalogData}
                              currentUser={currentUser}
                              isLoading={index === lastIndex && isLoading}
                            />
                            <PlaygroundChatMessage
                              model={model}
                              message={message}
                              index={index}
                              isLoading={index === lastIndex && isLoading}
                              isError={message.role === 'error'}
                              lastIndex={index === lastIndex}
                              handleClearHistory={() => {}}
                            />
                          </div>
                        ))}
                      </div>
                    ) : (
                      blankSlate
                    )}
                  </div>
                </PageLayout.Content>
              </PageLayout>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
