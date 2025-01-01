import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {testIdProps} from '@github-ui/test-id-props'
import {CommandButton, GlobalCommands} from '@github-ui/ui-commands'
import {useUser} from '@github-ui/use-user'
import {SquareFillIcon, StackIcon} from '@primer/octicons-react'
import {Button, PageLayout, Stack} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {Suspense, lazy, useCallback, useEffect, useRef, useState} from 'react'
import {useModels} from '../contexts/ModelsContext'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import {findModel} from '../models'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {referencedVariablesInPrompt, replaceVarsInMessages} from '../variables'
import {CompletionMessage} from './CompletionMessage'
import {CompletionMessageHeader} from './CompletionMessageHeader'
import ModelPicker from './ModelPicker'
import ParameterSettingsMenu from './ParameterSettingsMenu'
import styles from './Prompt.module.css'
import {PromptFileHeader} from './PromptFileHeader'
import {PromptMessageEditor} from './PromptMessageEditor'
import {VariablesDialog} from './VariablesDialog'
import {ViewSwitcher} from './ViewSwitcher'
import {PromptLayout} from './PromptLayout'

// Lazy load as WebCommitDialog is not compatible with SSR
const WebCommitDialog = lazy(async () => {
  const module = await import('@github-ui/web-commit-dialog')
  return {default: module.WebCommitDialog}
})

export type PromptProps = {
  modelClient: AzureModelClient
}

export function Prompt({modelClient}: PromptProps) {
  const {variables, messages, prompts, isLoading, isDirty} = usePromptCompareState()
  const activePrompt = prompts[0]! // TODO: CS: This will always be there, better way to express this as a type?

  const canRun =
    !!activePrompt.model &&
    activePrompt.messages &&
    activePrompt.messages?.length > 0 &&
    activePrompt.messages.some(x => x.message.trim() !== '')

  const referencedVariables = new Set<string>(referencedVariablesInPrompt(activePrompt))

  const lastIndex = messages.length - 1
  const manager = usePromptCompareManager()

  const models = useModels()

  // Try to map model identified in the prompt to an available model. The prompt might not have a model specified,
  // or the identifier might not match a model we have
  const model = findModel(activePrompt.model ?? '', models)

  const {currentUser} = useUser()

  const [commitOpen, setCommitOpen] = useState(false)

  // Scrolling behavior for inference
  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const scrollToBottom = useCallback(() => {
    messagesContainerRef.current?.scrollIntoView(false)
  }, [])

  useEffect(() => {
    requestAnimationFrame(scrollToBottom)
  }, [messages, scrollToBottom])

  const handleRun = useCallback(
    (vars: Record<string, string>) => {
      if (!model) {
        // Running is only enabled if we have a model, check again just to be sure (and to make TS happy)
        return
      }

      const variablesWithoutValue = Array.from(referencedVariables.keys()).filter(v => !vars[v])
      if (variablesWithoutValue.length > 0) {
        // One of the referenced variables doesn't have a value, ask the user for a value first, do not run the prompt.
        setShowRunVariablesDialog(true)
        return
      }

      const expandedPrompt = replaceVarsInMessages(activePrompt.messages, vars)

      const systemPrompt = expandedPrompt.find(x => x.role === 'system')?.message ?? ''
      const userPrompt = expandedPrompt.find(x => x.role === 'user')?.message ?? ''
      manager.sendMessage(model, modelClient, systemPrompt, userPrompt)
    },
    [activePrompt, manager, model, modelClient, referencedVariables],
  )

  const handleStop = useCallback(() => {
    modelClient.stopStreamingMessages(0)
  }, [modelClient])

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
        // Persist variable values
        manager.setVariables(v)

        // Immediately run the prompt with the updated variable values
        handleRun(v)
      }
    },
    [manager, handleRun],
  )

  const blankSlate = (
    <div className={styles.blankSlate}>
      <Blankslate>
        <Blankslate.Visual>
          <StackIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>Iterate on your prompt</Blankslate.Heading>
        <Blankslate.Description>
          Use the prompt editor to run a single prompt repeatedly, refining it and adjusting{' '}
          <code>{'{{variables}}'}</code> to achieve the perfect response.
        </Blankslate.Description>
      </Blankslate>
    </div>
  )

  return (
    <>
      {showEditVariablesDialog && (
        <VariablesDialog
          primaryTitle="Save"
          variables={variables}
          availableVariables={referencedVariables}
          onClose={handleCloseEditVariablesDialog}
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

      {commitOpen && (
        <Suspense fallback={<div>Loading...</div>}>
          <WebCommitDialog
            description="Updated"
            dialogState="pending"
            isQuickPull={false}
            helpUrl="https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/committing-changes-to-your-project"
            message="Updated prompt"
            onSave={() => {}}
            refName="main"
            setAuthorEmail={() => {}}
            setDescription={() => {}}
            setMessage={() => {}}
            setDialogState={() => {
              setCommitOpen(false)
            }}
            webCommitInfo={{
              authorEmails: ['cschleiden@live.de'],
              canCommitStatus: 'allowed',
              dcoSignoffEnabled: false,
              defaultEmail: 'cschleiden@live.de',
              defaultNewBranchName: 'patch-1',
              commitOid: '123',
              lockedOnMigration: false,
              shouldFork: false,
              repoHeadEmpty: false,
              saveUrl: '',
              suggestionsUrlEmoji: '',
              suggestionsUrlMention: '',
              suggestionsUrlIssue: '',
              shouldUpdate: true,
              pr: '',
            }}
          />
        </Suspense>
      )}

      <PromptLayout>
        <PromptFileHeader prompt={activePrompt} canCommit={!!isDirty} setCommitOpen={setCommitOpen} />

        <div className="border rounded-2 flex-1 d-flex flex-column overflow-hidden">
          <div className={styles.toolbar}>
            <ViewSwitcher />
            <div className="flex-1" />
            <Button
              size="small"
              className="mr-2"
              onClick={() => setShowVariablesDialog(true)}
              {...testIdProps('edit-variables')}
            >
              Variables
            </Button>
          </div>

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
                <Stack gap="condensed" justify="space-between" direction="horizontal" className="p-3">
                  <ModelPicker
                    selectedModel={model}
                    onSelect={m => {
                      manager.updatePrompt({
                        ...activePrompt,
                        model: m.original_name, // For a better user experience, we use just the name here
                      })
                    }}
                  />
                  <ParameterSettingsMenu
                    iconSize="medium"
                    model={model}
                    modelParameters={activePrompt.modelParameters ?? {}}
                    handleModelParamsChange={({key, value}) => {
                      // TODO: Validate parameters if validate is set
                      manager.updatePrompt({
                        ...activePrompt,
                        modelParameters: {
                          ...activePrompt.modelParameters,
                          [key]: value,
                        },
                      })
                    }}
                  />
                  <>
                    <GlobalCommands commands={{'github:submit-form': () => canRun && handleRun(variables)}} />
                    {isLoading ? (
                      <Button leadingVisual={SquareFillIcon} variant="danger" onClick={handleStop}>
                        Stop
                      </Button>
                    ) : (
                      <CommandButton
                        variant="primary"
                        commandId="github:submit-form"
                        disabled={canRun === false}
                        showKeybindingHint
                      >
                        Run
                      </CommandButton>
                    )}
                  </>
                </Stack>
                <form className="p-3">
                  <PromptMessageEditor
                    messages={activePrompt.messages}
                    updateMessages={updatedMessages => {
                      manager.updatePrompt({
                        ...activePrompt,
                        messages: updatedMessages,
                      })
                    }}
                  />
                </form>
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
                            currentUser={currentUser}
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
                    blankSlate
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
