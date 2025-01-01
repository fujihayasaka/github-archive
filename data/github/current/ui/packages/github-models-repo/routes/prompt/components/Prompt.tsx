import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {Button, PageLayout, Stack} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useModels} from '../contexts/ModelsContext'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import {findModel} from '../models'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {referencedVariablesInPrompt} from '../variables'
import {CompletionMessage} from './CompletionMessage'
import {CompletionMessageHeader} from './CompletionMessageHeader'
import ModelPicker from './ModelPicker'
import ParameterSettings, {ParameterSettingsButton, useParameterSettings} from './ParameterSettings'
import styles from './Prompt.module.css'
import {PromptFileHeader} from './PromptFileHeader'
import {PromptLayout} from './PromptLayout'
import {PromptMessageEditor} from './PromptMessageEditor'
import {PromptMessagePair} from './PromptMessagePair'
import {VariablesDialog} from './VariablesDialog'

import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {BookIcon} from '@primer/octicons-react'
import useActivePrompt from '../hooks/use-active-prompt'
import useActivePromptModel from '../hooks/use-active-prompt-model'
import usePromptRunButton from '../hooks/use-prompt-run-button'
import {getSystemMessage, getUserMessage, type PromptConfig} from '../prompts'
import {createSystemMessage, createUserMessage, extractMessagePairs, updateMessagePairs} from '../utils/message-utils'
import {PromptBlankslate} from './PromptBlankslate'
import {PromptToolbar} from './PromptToolbar'
import PromptWebCommitDialog from './PromptWebCommitDialog'
import type {RepoModel} from '../../../types'
import {testIdProps} from '@github-ui/test-id-props'

export type PromptProps = {
  modelClient: AzureModelClient
  isNewPrompt: boolean
}

export function Prompt({modelClient, isNewPrompt}: PromptProps) {
  const {variables, messages, isLoading, isDirty} = usePromptCompareState()
  const activePrompt = useActivePrompt()
  const model = useActivePromptModel()
  const parameterSettingsProps = useParameterSettings()

  const [dialogState, setDialogState] = useState<WebCommitDialogState>('closed')
  const [showEditVariablesDialog, setShowEditVariablesDialog] = useState(false)
  const [showRunVariablesDialog, setShowRunVariablesDialog] = useState(false)

  const messagePairFlagEnabled = useFeatureFlag('github_models_prompt_message_pair')

  const referencedVariables = useMemo(() => new Set<string>(referencedVariablesInPrompt(activePrompt)), [activePrompt])

  const lastIndex = messages.length - 1
  const manager = usePromptCompareManager()
  const models = useModels()

  const promptRunButtonProps = usePromptRunButton(modelClient, setShowRunVariablesDialog)

  useEffect(() => {
    const {search} = globalThis.location
    if (isNewPrompt && search.includes('sample')) {
      manager.updatePrompt({
        ...activePrompt,
        ...samplePrompt,
      })
      manager.setVariables({
        ...variables,
        input: sampleInput,
      })
    }

    // For new prompts: Default to gpt-4o model in the model picker.
    if (isNewPrompt) {
      const defaultModel = findModel('gpt-4o', models)

      if (defaultModel) {
        manager.updatePrompt({
          ...activePrompt,
          model: defaultModel.original_name,
        })
      }
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [models.length]) // we need this because models aren't loaded on first render, but using [models] causes unnecessary re-renders

  // Scrolling behavior for inference
  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const scrollToBottom = useCallback(() => {
    messagesContainerRef.current?.scrollIntoView(false)
  }, [])

  useEffect(() => {
    requestAnimationFrame(scrollToBottom)
  }, [messages, scrollToBottom])

  const handleCloseEditVariablesDialog = useCallback(
    (v?: Record<string, string>) => {
      if (v) {
        manager.setVariables(v)
      }
      setShowEditVariablesDialog(false)
    },
    [manager],
  )

  const handleCloseRunVariablesDialog = useCallback(
    (v?: Record<string, string>) => {
      setShowRunVariablesDialog(false)

      if (v) {
        // Persist variable values
        manager.setVariables(v)

        // Immediately run the prompt with the updated variable values
        promptRunButtonProps.handleRun(v)
      }
    },
    [manager, promptRunButtonProps],
  )

  const handleModelSelect = useCallback(
    (m: RepoModel) => {
      manager.updatePrompt({
        ...activePrompt,
        model: m.original_name, // For a better user experience, we use just the name here
      })
      promptRunButtonProps.handleStop()
      manager.resetHistory(promptRunButtonProps.setTokenUsage)
    },
    [activePrompt, manager, promptRunButtonProps],
  )

  useEffect(() => {
    const promptSettings = globalThis.history.state?.usr
    if (promptSettings) {
      const {systemPrompt} = promptSettings
      const newMessages = [createSystemMessage(systemPrompt), createUserMessage('')]
      manager.updatePrompt({
        modelParameters: promptSettings.params,
        model: promptSettings.model,
        messages: newMessages,
      })
    }
  }, [manager])

  return (
    <>
      {showEditVariablesDialog && (
        <VariablesDialog
          primaryTitle="Save"
          variables={variables}
          availableVariables={referencedVariables}
          onClose={handleCloseEditVariablesDialog}
          model={model}
        />
      )}

      {showRunVariablesDialog && (
        <VariablesDialog
          primaryTitle="Run"
          requireValues
          variables={variables}
          availableVariables={referencedVariables}
          onClose={handleCloseRunVariablesDialog}
        />
      )}

      {(dialogState === 'pending' || dialogState === 'saving') && (
        <PromptWebCommitDialog activePrompt={activePrompt} dialogState={dialogState} setDialogState={setDialogState} />
      )}

      <PromptLayout>
        <PromptFileHeader prompt={activePrompt} isDirty={isDirty} setDialogState={setDialogState} />

        <div className="border rounded-2 flex-1 d-flex flex-column overflow-hidden">
          <PromptToolbar model={model} {...promptRunButtonProps} />

          <div className={styles.mainWrapper}>
            <PageLayout padding="none" containerWidth="full" rowGap="none" columnGap="none">
              <PageLayout.Pane
                resizable
                position="start"
                divider="none"
                padding="none"
                sticky
                aria-label="Prompt editor"
              >
                <Stack gap="condensed" justify="space-between" direction="horizontal" className="pt-3 px-3 mb-3">
                  <ModelPicker
                    selectedModel={model}
                    onSelect={m => {
                      handleModelSelect(m)
                    }}
                  />

                  <ParameterSettingsButton {...parameterSettingsProps} />
                </Stack>

                <ParameterSettings
                  className="px-3 mb-3"
                  {...parameterSettingsProps}
                  setParameters={modelParameters => {
                    manager.updatePrompt({
                      ...activePrompt,
                      modelParameters,
                    })
                  }}
                  setResponseFormat={responseFormat => {
                    manager.updatePrompt({
                      ...activePrompt,
                      responseFormat,
                    })
                  }}
                  setJsonSchema={jsonSchema => {
                    manager.updatePrompt({
                      ...activePrompt,
                      jsonSchema,
                    })
                  }}
                />

                <form className="px-3 mb-3">
                  <PromptMessageEditor
                    selectedModel={model}
                    messages={activePrompt.messages}
                    updateMessages={updatedMessages => {
                      manager.updatePrompt({
                        ...activePrompt,
                        messages: updatedMessages,
                      })
                    }}
                  />
                </form>

                {messagePairFlagEnabled ? (
                  <div className="px-3 mb-3">
                    <PromptMessagePair
                      messagePairs={extractMessagePairs(activePrompt.messages || [])}
                      setMessagePairs={pairs => {
                        const updatedMessages = updateMessagePairs(activePrompt.messages || [], pairs)
                        manager.updatePrompt({
                          ...activePrompt,
                          messages: updatedMessages,
                        })
                      }}
                      variableKeys={Array.from(referencedVariables)}
                      onVariablesClick={() => setShowEditVariablesDialog(true)}
                      variablesIcon={BookIcon}
                    />
                  </div>
                ) : (
                  <div className="px-3 mb-3">
                    <Button
                      onClick={() => setShowEditVariablesDialog(true)}
                      leadingVisual={BookIcon}
                      {...testIdProps('edit-variables')}
                    >
                      Variables
                    </Button>
                  </div>
                )}
              </PageLayout.Pane>
              <PageLayout.Content as="div" className={styles.promptBody}>
                <div className="d-flex flex-column">
                  {model && messages?.length > 0 ? (
                    <div className="p-3 overflow-auto flex-1" ref={messagesContainerRef}>
                      {messages.map((message, index) => (
                        // eslint-disable-next-line @eslint-react/no-array-index-key
                        <div key={`${message.role}-${index}`}>
                          <CompletionMessageHeader
                            message={message}
                            model={model}
                            isLoading={index === lastIndex && isLoading}
                          />
                          <CompletionMessage
                            model={model}
                            message={message}
                            index={index}
                            isLoading={index === lastIndex && isLoading}
                            isError={message.role === 'error'}
                            lastIndex={index === lastIndex}
                          />
                        </div>
                      ))}
                    </div>
                  ) : (
                    <PromptBlankslate />
                  )}
                </div>
              </PageLayout.Content>
            </PageLayout>
          </div>
        </div>
      </PromptLayout>
    </>
  )
}

const samplePrompt: PromptConfig = {
  model: 'gpt-4o',
  messages: [
    getSystemMessage('You are a helpful assistant that breaks down action items from a meeting'),
    getUserMessage('Pull out the action items from this meeting transcript: {{input}}'),
  ],
}

const sampleInput = `Meeting Transcript\nDate: October 25, 2023\nTime: 10:00 AM – 11:30 AM\nAttendees: Aisha, Carlos, Mei-Lin, Jamal, Chloe, Ravi, Elena, Michael, Fatima, Liam\n\nFacilitator: Carlos\nScribe: Mei-Lin\n\nCarlos: Good morning, everyone. Thanks for joining on time. Let's get started. The agenda today is project updates, aligning deadlines for Q4 deliverables, and planning the next sprint. Anything else we need to add before diving in?\n\nChloe: Yeah, if we have time at the end, let's discuss the feedback we got from the client demo.\n\nCarlos: Got it. We'll add that to the tail end if we have time. Let's start with project updates. Aisha?\n\nAisha: Sure. The API integration is almost done—about 80% complete. The main issue is the new authentication module. It's slowing us down more than expected, but I'm escalating it with the IT team to get support.\n\nRavi: On the design side, the UI for the new dashboard is in its final stages. We're targeting a handoff to development next Wednesday.\n\nFatima: That's great. The sales team is really happy with how things are shaping up, but they're waiting on that dashboard prototype before they can move forward with client walkthroughs.\n\nCarlos: Okay, so action items here—Aisha, can you make a JIRA ticket outlining the specifics of the authentication issue for better visibility?\n\nAisha: Yeah, I'll prioritize that and get it out by the end of the day.\n\nCarlos: Thanks. Ravi, can you follow up with us by Friday to confirm the final handoff date for the UI?\n\nRavi: Will do.\n\nCarlos: Alright, let's move to the next topic—timelines for Q4 deliverables. Jamal, can you kick us off?\n\nJamal: Sure. We've hit a two-week delay on the backend implementation. The issue is whether we need to move the entire timeline or if we can compress it somewhere else.\n\nMichael: We might be able to recover some time if we overlap the QA process with the internal review stage. It's not ideal, but it's an option.\n\nElena: I'm a little worried about compromising quality. If QA is rushed and bugs slip through, we'll pay for it later. I think we should look at using the buffer in the UAT phase instead.\n\nCarlos: Okay. It sounds like we need a deeper conversation to come up with a solution. Elena, Michael, Jamal—can the three of you meet tomorrow to revise the timeline and suggest adjustments?\n\nElena: Works for me. Let's say 2 PM?\n\nMichael: That works.\n\nJamal: Same here. I'll set something up on the calendar.\n\nCarlos: Perfect. Let's keep going—sprint priorities. Liam, where are we on this?\n\nLiam: We're seeing a surge in customer support tickets recently, mostly related to minor feature bugs. I think addressing the top offenders needs to be a key priority in the next sprint.\n\nChloe: Agreed. If we can identify, say, the top 10 recurring issues and prioritize fixing those, it'll reduce the noise considerably.\n\nCarlos: Good suggestion. Liam, can you pull that data and filter for the most pressing bugs?\n\nLiam: On it. I'll have it ready for sprint planning on Monday.\n\nCarlos: Thanks. Now, Chloe, you wanted to bring up feedback from the demo?\n\nChloe: Yeah, one of our key clients mentioned that they'd like more customization options in the reporting features. They brought it up during the Q&A after the demo.\n\nFatima: Makes sense. We've heard somewhat similar suggestions in the past. I think we should scope it out and see what's feasible in the short term versus a future phase.\n\nChloe: Fatima, let's sync up after this meeting and figure out what's doable.\n\nFatima: Sounds good. I'll block some time with you for later today to dive into it.\n\nCarlos: Great. Alright, we covered the agenda. Let's quickly go over the action items to make sure we're aligned.\n\nMei-Lin: I've got a draft list here. Should I go ahead?\n\nCarlos: Yes, please.\n\nMei-Lin: Okay: Aisha will update JIRA with details on the authentication issue by the end of today. Ravi will confirm the UI handoff date by Friday. Elena, Michael, and Jamal will meet tomorrow at 2 PM to draft a revised timeline. Liam will pull the top 10 recurring bugs for sprint planning on Monday. Chloe and Fatima will meet today to review the client feedback on reporting. Lastly, I'll send the full meeting notes later today.\n\nCarlos: Perfect. I'll also schedule the next meeting for Wednesday, November 1, and get the calendar invite out by the end of the day.\n\nMichael: Works for me.\n\nChloe: Same.\n\nCarlos: Alright, thanks, everyone. Great work. Let's adjourn. Have a good rest of your day!\n\nMeeting adjourned at 11:25 AM.`
