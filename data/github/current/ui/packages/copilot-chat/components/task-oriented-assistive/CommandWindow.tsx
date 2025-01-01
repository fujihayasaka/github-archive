import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {CommandIconButton, CommandKeybindingHint, ScopedCommands} from '@github-ui/ui-commands'
import {useNavigate} from '@github-ui/use-navigate'
import {ScreenFullIcon, SquareFillIcon} from '@primer/octicons-react'
import {Box, Button, IconButton, TextInput} from '@primer/react'
import {Dialog, KeybindingHint, SkeletonText} from '@primer/react/experimental'
import {useCallback, useMemo, useRef, useState} from 'react'

import {copilotChatHeaderButtonID} from '../../utils/constants'
import {COPILOT_PATH} from '../../utils/copilot-chat-helpers'
import {CopilotChatIntents} from '../../utils/copilot-chat-types'
import {useChatState} from '../../utils/CopilotChatContext'
import {useChatManager} from '../../utils/CopilotChatManagerContext'
import {capitalize} from '../../utils/string'
import {ChatMessage} from '../ChatMessage'
import {ChatMessageProvider} from '../ChatMessageContext'
import {ChatScrollContainer} from '../ChatScrollContainer'
import CopilotAnimation, {CopilotAnimationType} from '../CopilotAnimation'
import {Feedback} from '../Feedback'
import {useEntitlement} from '../quota/EntitlementContext'
import {CommandList} from './CommandList'
import type {Command} from './commands'
import styles from './CommandWindow.module.css'
import {ContextLabel} from './ContextLabel'
import {TopicLabel} from './TopicLabel'
import {useCommandContext} from './use-command-context'
import {useCommands} from './use-commands'
import {useSelectedIndex} from './use-selected-index'

const CommandWindowState = {
  Initial: 'initial',
  Complete: 'complete',
} as const

type CommandWindowState = (typeof CommandWindowState)[keyof typeof CommandWindowState]

// Component for task-oriented assistive prototype
export function CommandWindow(): JSX.Element | undefined {
  const state = useChatState()
  const {entryPointId, chatIsOpen, currentRepository} = state

  const manager = useChatManager()
  const thread = manager.getSelectedThread(state)

  const {reloadQuota} = useEntitlement()
  const navigate = useNavigate()

  const [windowState, setWindowState] = useState<CommandWindowState>(CommandWindowState.Initial)

  const inputRef = useRef<HTMLInputElement>(null)
  const [inputValue, setInputValue] = useState<string>('')

  const currentContext = useCommandContext()
  const commands = useCommands(
    currentContext?.type,
    currentContext && 'persona' in currentContext ? currentContext.persona : undefined,
    inputValue,
  )
  const {selectedIndex, selectPrevious, selectNext} = useSelectedIndex(commands.length - 1)

  const copilotMessage = useMemo(() => {
    return state.messages.findLast(m => m.role === 'assistant')
  }, [state.messages])

  // --- HANDLERS

  const handleDialogClose = useCallback(
    (gesture: string): void => {
      setWindowState(CommandWindowState.Initial)
      setInputValue('')

      manager.closeChat()
      if (gesture === 'escape') {
        const entryId = entryPointId ?? copilotChatHeaderButtonID
        const entryElement = document.getElementById(entryId)
        const scrollX = window.scrollX
        const scrollY = window.scrollY

        // Persist current scroll position by delaying focus
        setTimeout(() => {
          entryElement?.focus()
          window.scrollTo(scrollX, scrollY)
        }, 0)
      }
    },
    [manager, entryPointId],
  )

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setInputValue(e.currentTarget.value)
    setWindowState(CommandWindowState.Initial)
  }, [])

  const handleMessageSend = useCallback(
    async (command: Command) => {
      setInputValue(command.name)

      const content = command.prompt
      if (content.trim() === '') return

      reloadQuota()

      // This dialog is intended to be focused on a single task, so clear any existing messages.
      if (thread) {
        await manager.clearThread(thread)
      }

      // The sendChatMessage call will block until we start streaming a response.
      // So we set the dialog state here to make sure we can show that streaming response.
      setWindowState(CommandWindowState.Complete)

      await manager.sendChatMessage({
        content,
        thread,
        references: state.currentReferences,
        topic: state.currentRepository,
        context: state.context,
        customInstructions: state.customInstructions,
        intent: command.intent || CopilotChatIntents.conversation,
        modeOverride: command.type === 'custom' ? 'assistive' : 'task-oriented-assistive',
      })

      // After the response completes, highlight the input to allow the user to modify the command.
      setTimeout(() => {
        inputRef?.current?.select?.()
        window.scrollTo(scrollX, scrollY)
      }, 0)
    },
    [
      manager,
      reloadQuota,
      state.context,
      state.currentReferences,
      state.currentRepository,
      state.customInstructions,
      thread,
    ],
  )

  const handleMessageSubmit = useCallback(async () => {
    const command = commands[selectedIndex]
    if (!command) {
      return
    }

    await handleMessageSend(command)
  }, [selectedIndex, commands, handleMessageSend])

  const handleMessageStop = useCallback(() => manager.stopStreaming(), [manager])

  const handleOpenInImmersive = useCallback(() => {
    if (thread) {
      navigate(`${COPILOT_PATH}/c/${thread.id}`)
    } else if (currentRepository) {
      navigate(`${COPILOT_PATH}/r/${currentRepository.ownerLogin}/${currentRepository.name}`)
    } else {
      navigate(COPILOT_PATH)
    }
  }, [currentRepository, navigate, thread])

  // --- RENDERERS

  const renderCommandList = (): JSX.Element | undefined => {
    if (windowState !== CommandWindowState.Initial) {
      return undefined
    }

    let headingText = capitalize(currentContext?.type?.replaceAll('-', ' ') ?? 'Select an action')
    if (inputValue) {
      headingText = 'Results found'
    }
    if (commands.every(command => command.type === 'custom')) {
      headingText = 'No results found'
    }

    return (
      <CommandList
        headingText={headingText}
        commands={commands.map((command, index) => {
          return {
            ...command,
            selected: index === selectedIndex,
          }
        })}
        onSelect={async command => await handleMessageSend(command)}
      />
    )
  }

  const renderCommandInput = (): JSX.Element => {
    const isLoading = state.isWaitingOnCopilot
    return (
      <div className="d-flex flex-column">
        <ScopedCommands
          commands={{
            'copilot-chat:task-oriented-select-previous': selectPrevious,
            'copilot-chat:task-oriented-select-next': selectNext,
            'copilot-chat:send-message': () => void handleMessageSubmit(),
            'copilot-chat:stop-response': () => void handleMessageStop(),
            'copilot-chat:open-immersive': handleOpenInImmersive,
          }}
        >
          <ScopedCommands.LimitKeybindingScope commandIds={['copilot-chat:send-message', 'copilot-chat:stop-response']}>
            <TextInput
              ref={inputRef}
              size="large"
              leadingVisual={<ContextLabel context={currentContext} />}
              trailingVisual={
                <div className="d-flex flex-row">
                  {isLoading && (
                    <CommandIconButton
                      variant="invisible"
                      icon={SquareFillIcon}
                      className="fgColor-danger"
                      commandId="copilot-chat:stop-response"
                    />
                  )}
                  <div className={styles.copilotAvatar}>
                    <CopilotAnimation
                      animationType={isLoading ? CopilotAnimationType.Thinking : CopilotAnimationType.Idle}
                      loopAnimation
                      mode="assistive"
                    />
                  </div>
                </div>
              }
              value={inputValue}
              onChange={handleInputChange}
              disabled={isLoading}
              placeholder="Search for actions"
            />
          </ScopedCommands.LimitKeybindingScope>
        </ScopedCommands>
      </div>
    )
  }

  const renderResponse = (): JSX.Element | undefined => {
    const isLoading = state.messagesLoading.state === 'loading'
    const isLoaded = state.messagesLoading.state === 'loaded'
    const isError = state.messagesLoading.state === 'error'

    return (
      <ChatScrollContainer>
        <Box
          className={styles.chatMessageWrapper}
          sx={{
            // HACK: targeting a child component via CSS modules doesn't work
            '.message-container': {
              padding: 0,
              display: 'block',
              '> :first-child': {
                // Hide the Copilot avatar in the message area
                display: 'none',
              },
              '.message-actions': {
                // Message actions doesn't obey the `excludeFeedback` prop :(
                display: 'none',
              },
            },
          }}
        >
          {isLoading && <>Loading...</>}
          {isError && <>Error...</>}
          {state.isWaitingOnCopilot &&
            (state.streamingMessage ? (
              <ChatMessage
                key={state.streamingMessage.id}
                message={state.streamingMessage}
                isStreaming
                inputRef={inputRef}
                excludeFeedback
              />
            ) : (
              <SkeletonText lines={3} />
            ))}
          {isLoaded && !isLoading && copilotMessage && (
            <ChatMessage
              key={copilotMessage.id}
              message={copilotMessage}
              isStreaming={copilotMessage.id === state.streamingMessage?.id}
              inputRef={inputRef}
              excludeFeedback
            />
          )}
        </Box>
      </ChatScrollContainer>
    )
  }

  const renderBody = (): JSX.Element | undefined => {
    if (windowState === CommandWindowState.Initial) {
      return renderCommandList()
    }

    if (windowState === CommandWindowState.Complete) {
      return renderResponse()
    }

    return undefined
  }

  const renderFooter = (): JSX.Element | undefined => {
    if (windowState === CommandWindowState.Initial) {
      return (
        <>
          <div>Select an action</div>
          <div className="d-flex flex-row">
            <Button
              className="fgColor-muted"
              variant="invisible"
              onClick={() => handleDialogClose('close-button')}
              trailingVisual={<KeybindingHint keys="Esc" />}
            >
              Close
            </Button>
            <Button
              className="fgColor-muted"
              variant="invisible"
              onClick={handleMessageSubmit}
              trailingVisual={<CommandKeybindingHint commandId="copilot-chat:send-message" />}
            >
              Confirm
            </Button>
          </div>
        </>
      )
    }

    if (windowState === CommandWindowState.Complete) {
      return (
        <>
          <div>
            {copilotMessage && (
              <>
                <ChatMessageProvider message={copilotMessage}>
                  <Feedback iconSize="small" returnFocusRef={inputRef} />
                </ChatMessageProvider>
                <CopyToClipboardButton textToCopy={copilotMessage.content ?? ''} ariaLabel="Copy to clipboard" />
              </>
            )}
          </div>
          <div className="d-flex flex-row">
            <Button
              className="fgColor-muted"
              variant="invisible"
              onClick={() => handleDialogClose('close-button')}
              trailingVisual={<KeybindingHint keys="Esc" />}
            >
              Close
            </Button>
            <Button
              className="fgColor-muted"
              variant="invisible"
              onClick={handleOpenInImmersive}
              trailingVisual={<CommandKeybindingHint commandId="copilot-chat:open-immersive" />}
            >
              Continue in Chat
            </Button>
          </div>
        </>
      )
    }

    return undefined
  }

  if (!chatIsOpen) {
    return undefined
  }

  return (
    <Dialog
      className={styles.dialog}
      initialFocusRef={inputRef}
      onClose={handleDialogClose}
      renderHeader={() => {
        return (
          <Dialog.Header className="d-flex flex-row flex-justify-between flex-items-center px-4 pt-2 mr-n3 box-shadow-none">
            <div className="fgColor-muted">
              <TopicLabel topic={state.currentRepository} />
            </div>
            <div data-testid="copilot-assistive-command-window" />

            <div>
              <IconButton
                size="small"
                variant="invisible"
                icon={ScreenFullIcon}
                aria-label="Take conversation to immersive"
                disabled={state.isWaitingOnCopilot}
                onClick={handleOpenInImmersive}
              />
              <Dialog.CloseButton onClose={() => handleDialogClose('close-button')} />
            </div>
          </Dialog.Header>
        )
      }}
      renderBody={() => {
        return (
          <Dialog.Body className="py-1">
            {renderCommandInput()}
            {renderBody()}
          </Dialog.Body>
        )
      }}
      renderFooter={() => {
        // There's no footer while waiting for Copilot's response
        if (state.isWaitingOnCopilot) {
          return undefined
        }

        return (
          <Dialog.Footer className="d-flex flex-row flex-justify-between flex-items-center px-3 py-2 fgColor-muted">
            {renderFooter()}
          </Dialog.Footer>
        )
      }}
    />
  )
}
