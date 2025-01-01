import {Autocomplete} from '@github-ui/copilot-chat/components/Autocomplete'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatInput, useTextareaPreview} from '@github-ui/copilot-chat/utils/use-chat-input'
import {sendEvent} from '@github-ui/hydro-analytics'
import {PaperAirplaneIcon, SquareFillIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import type {RefObject} from 'react'
import {useRef} from 'react'

import {copilotChatTextAreaId} from '../utils/constants'
import {AttachmentMenu} from './AttachmentMenu'
import classes from './ChatInput.module.css'
import {ChatInputReferences} from './ChatInputReferences'

interface ChatInputProps {
  textAreaRef?: React.RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
  onAbort?: () => void
  isLoading?: boolean
  isStreaming?: boolean
}

export const ChatInput = (props: ChatInputProps) => {
  const state = useChatState()

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
  } = useChatInput({
    isLoading: props.isLoading,
    onSubmit: props.onSubmit,
    onAbort: props.onAbort,
    textAreaRef: props.textAreaRef,
  })

  const placeholderText = props.isLoading
    ? `Copilot is responding…`
    : state.defaultRecipient
      ? undefined
      : 'Ask Copilot'

  if (state.defaultRecipient && text === '' && !typingHasStarted) {
    setText(`@${state.defaultRecipient} `)
  }

  const attachmentButtonRef = useRef<HTMLButtonElement>(null)

  return (
    <form className={classes.container}>
      <ChatInputReferences className={classes.attachments} returnFocusRef={attachmentButtonRef} />

      <div className={classes.inputContainer} ref={textAreaPreviewContainerRef}>
        <Autocomplete textAreaRef={textAreaRef}>
          <textarea
            autoFocus
            id={copilotChatTextAreaId}
            className={classes.input}
            autoComplete="off"
            autoCorrect="off"
            spellCheck="false"
            aria-multiline="true"
            ref={textAreaRef}
            onKeyDown={handleKeyDown}
            onScroll={handleScroll}
            onChange={handleChange}
            placeholder={placeholderText}
            value={text}
            data-react-autofocus
            onFocus={() => sendEvent('dotcom_chat.activate', {target: 'CHAT_INPUT_FOCUSED', mode: 'immersive'})}
          />
        </Autocomplete>
        <TextareaPreview text={text} textareaPreviewRef={textareaPreviewRef} />
      </div>

      <div className={classes.trailingActions}>
        <AttachmentMenu inputRef={textAreaRef} inputOnChange={handleChange} ref={attachmentButtonRef} />
        {props.isStreaming ? (
          <StopButton onSubmit={handleStop} />
        ) : (
          <SubmitButton isLoading={props.isLoading} onSubmit={handleSubmit} />
        )}
      </div>
    </form>
  )
}

function TextareaPreview(props: {text: string; textareaPreviewRef: RefObject<HTMLDivElement>}) {
  const {text, textareaPreviewRef} = props
  const {mention, textAfterMention} = useTextareaPreview(props)

  return (
    <div
      id="copilot-chat-textarea-preview"
      aria-hidden
      className={classes.inputPreview}
      ref={textareaPreviewRef}
      role="presentation"
    >
      {mention ? (
        <>
          <span className="chat-token">{mention}</span>
          {textAfterMention}
        </>
      ) : (
        text
      )}
    </div>
  )
}

function SubmitButton({isLoading, onSubmit}: {isLoading?: boolean; onSubmit: () => void}) {
  return (
    <IconButton
      variant="invisible"
      size="medium"
      icon={PaperAirplaneIcon}
      aria-label="Send now"
      disabled={isLoading}
      tooltipDirection="n"
      onClick={() => {
        sendEvent('dotcom_chat.activate', {target: 'CHAT_MESSAGE_SEND', mode: 'immersive'})
        onSubmit()
      }}
    />
  )
}

function StopButton({onSubmit}: {onSubmit: () => void}) {
  return (
    // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
    <IconButton
      variant="invisible"
      size="medium"
      unsafeDisableTooltip
      onClick={() => {
        sendEvent('dotcom_chat.activate', {target: 'CHAT_MESSAGE_STOP', mode: 'immersive'})
        onSubmit()
      }}
      icon={SquareFillIcon}
      aria-label="Stop response"
      tooltipDirection="w"
      sx={{bg: 'danger.subtle', color: 'danger.fg', ':hover': {bg: 'danger.muted'}}}
    />
  )
}
