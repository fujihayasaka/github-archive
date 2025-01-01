import {testIdProps} from '@github-ui/test-id-props'
import {PaperAirplaneIcon, SquareFillIcon} from '@primer/octicons-react'
import {Box, Button, Heading, IconButton, Popover, Textarea} from '@primer/react'
import type {RefObject} from 'react'

import {copilotChatTextAreaId} from '../utils/constants'
import {isRepository} from '../utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {useChatInput, useTextareaPreview} from '../utils/use-chat-input'
import {AgentButton} from './AgentButton'
import {Autocomplete} from './Autocomplete'
import {InputTip} from './InputTip'
import {KnowledgeBaseToggleButton, KnowledgeSelectButton} from './KnowledgeSelectPanel'
import {ReferencesSelectButton} from './ReferencesSelectPanel'

interface ChatInputProps {
  textAreaRef?: React.RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
  onAbort?: () => void
  isLoading?: boolean
  isStreaming?: boolean
  panelWidth?: number
}

export const ChatInput = (props: ChatInputProps) => {
  const state = useChatState()
  const manager = useChatManager()
  const hasKnowledgeBases = state.knowledgeBases.length > 0

  const {
    typingHasStarted,
    textAreaRef,
    textareaPreviewRef,
    textAreaPreviewContainerRef,
    text,
    setText,
    handleSubmit,
    handleKeyDown,
    handleScroll,
    handleChange,
    handleStop,
    shouldShowKnowledge,
  } = useChatInput({
    isLoading: props.isLoading,
    onSubmit: props.onSubmit,
    onAbort: props.onAbort,
    textAreaRef: props.textAreaRef,
  })

  const shouldShowReferences = state.currentTopic && isRepository(state.currentTopic)

  const shouldShowInputTip = text.length < 3

  const placeholderText = props.isLoading
    ? `Copilot is responding…`
    : state.defaultRecipient
      ? undefined
      : 'Ask Copilot'

  if (state.defaultRecipient && text === '' && !typingHasStarted) {
    setText(`@${state.defaultRecipient} `)
  }

  return (
    <div>
      <Popover
        open={shouldShowKnowledge && hasKnowledgeBases && state.renderAttachKnowledgeBaseHerePopover}
        sx={{bottom: '57px'}}
        caret="bottom-left"
      >
        <Popover.Content sx={{mt: 2, width: '300px'}} className="color-shadow-medium">
          <Heading as="h4" sx={{fontSize: 2, mb: 2}}>
            An organization has shared a knowledge base with you
          </Heading>
          <p>
            Select a knowledge base to chat with Copilot and get answers from Markdown documentation stored in GitHub.
          </p>
          <Button
            onClick={() => {
              void manager.dismissAttachKnowledgeBaseHerePopover()
            }}
          >
            Got it
          </Button>
        </Popover.Content>
      </Popover>
      <Box
        className="copilot-chat-input"
        {...testIdProps('copilot-chat-input')}
        sx={{
          position: 'relative',
          width: '100%',
          overflow: 'hidden',
          display: 'flex',
          backgroundColor: 'canvas.default',
          border: '1px solid var(--borderColor-default, var(--color-border-default))',
          borderRadius: 'var(--borderRadius-medium)',

          '> div': {flex: 1},

          ':focus-within .copilot-keyboard-shortcuts': {
            opacity: 1,
            visibility: 'visible',
          },

          ':has(textarea:focus)': {
            outline: '2px solid var(--focus-outlineColor, var(--color-accent-emphasis))',
            borderColor: 'transparent',
          },
        }}
      >
        <div className="d-flex position-absolute" style={{left: 8, bottom: 8}}>
          {shouldShowKnowledge &&
            (copilotFeatureFlags.magicKBs ? (
              <KnowledgeBaseToggleButton />
            ) : (
              <KnowledgeSelectButton panelWidth={props.panelWidth} inputRef={textAreaRef} />
            ))}
          {shouldShowReferences && !copilotFeatureFlags.magicKBs && (
            <ReferencesSelectButton panelWidth={props.panelWidth} inputRef={textAreaRef} />
          )}
          <AgentButton inputRef={textAreaRef} inputOnChange={handleChange} />
        </div>

        <Box
          as="form"
          onSubmit={handleSubmit}
          className="width-full d-flex flex-column gap-2"
          sx={{
            '.copilot-chat-textarea::placeholder': {userSelect: 'none'},
          }}
        >
          <Box
            ref={textAreaPreviewContainerRef}
            sx={{
              maxHeight: '30dvh',
              overflowY: 'auto',
              flexGrow: 1,
              position: 'relative',
              '> div': {
                display: 'block',
              },
            }}
          >
            <Autocomplete textAreaRef={textAreaRef}>
              <Textarea
                id={copilotChatTextAreaId}
                className="copilot-chat-textarea"
                autoComplete="off"
                autoCorrect="off"
                spellCheck="false"
                role="textbox"
                aria-multiline="true"
                block
                ref={textAreaRef}
                resize="none"
                onKeyDown={handleKeyDown}
                onScroll={handleScroll}
                onChange={handleChange}
                placeholder={placeholderText}
                value={text}
                sx={{
                  border: 'none',
                  borderRadius: 0,
                  borderTopLeftRadius: 'var(--borderRadius-medium)',
                  borderTopRightRadius: 'var(--borderRadius-medium)',
                  display: 'contents',
                  '> textarea': {
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    padding: '8px 12px 2px',
                    background: 'transparent',
                    color: 'transparent',
                    caretColor: 'var(--fgColor-default, var(--color-fg-default))',
                    overflowY: 'hidden',
                    verticalAlign: 'middle',
                    resize: 'none',
                    zIndex: 1,
                  },
                  ':focus-within': {
                    boxShadow: 'none',
                  },
                }}
              />
            </Autocomplete>
            <TextareaPreview text={text} textareaPreviewRef={textareaPreviewRef} />
          </Box>

          <div className="d-flex flex-items-center flex-justify-end gap-2 px-2 pb-2">
            {shouldShowInputTip && <InputTip />}
            {props.isStreaming ? (
              <StopButton onSubmit={handleStop} />
            ) : (
              <SubmitButton isLoading={props.isLoading} onSubmit={handleSubmit} />
            )}
          </div>
        </Box>
      </Box>
    </div>
  )
}

function TextareaPreview(props: {text: string; textareaPreviewRef: RefObject<HTMLDivElement>}) {
  const {text, textareaPreviewRef} = props
  const {mention, textAfterMention} = useTextareaPreview(props)

  return (
    <Box
      id="copilot-chat-textarea-preview"
      aria-hidden
      className="textarea-preview"
      ref={textareaPreviewRef}
      role="presentation"
      sx={{
        // The styles and spacing here should mirror the textarea
        bg: 'canvas.default',
        borderRadius: 'var(--borderRadius-medium) var(--borderRadius-medium) 0 0',
        height: 'inherit',
        lineHeight: '20px',
        overflowY: 'hidden',
        padding: '8px 12px 2px',
        position: 'absolute',
        inset: 0,
        whiteSpace: 'pre-wrap',
        zIndex: 0,
        '> .chat-token': {
          backgroundColor: 'var(--bgColor-accent-muted, var(--color-accent-subtle))',
          borderRadius: 'var(--borderRadius-small)',
          color: 'var(--fgColor-accent, var(--color-accent-fg))',
        },
      }}
    >
      {mention ? (
        <>
          <span className="chat-token">{mention}</span>
          {textAfterMention}
        </>
      ) : (
        text
      )}
    </Box>
  )
}

function SubmitButton({isLoading, onSubmit}: {isLoading?: boolean; onSubmit: () => void}) {
  return (
    <IconButton
      variant="invisible"
      size="small"
      onClick={onSubmit}
      icon={PaperAirplaneIcon}
      aria-label="Send now"
      disabled={isLoading}
      tooltipDirection="n"
    />
  )
}

function StopButton({onSubmit}: {onSubmit: () => void}) {
  return (
    // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
    <IconButton
      variant="invisible"
      size="small"
      unsafeDisableTooltip
      onClick={onSubmit}
      icon={SquareFillIcon}
      aria-label="Stop response"
      tooltipDirection="w"
    />
  )
}
