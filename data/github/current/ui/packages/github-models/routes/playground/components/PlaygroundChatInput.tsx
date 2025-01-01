import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {PaperAirplaneIcon, SquareFillIcon} from '@primer/octicons-react'
import {Box, Textarea} from '@primer/react'
import {useCallback, useRef, type FormEvent} from 'react'
import type {ModelState} from '../../../types'
import {
  reachedMaxAttachments,
  supportImageWithoutText,
  useImageAttachmentSupported,
} from '../../../utils/image-validation'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import {usePlaygroundManager} from '../../../utils/playground-manager'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {AttachmentButton} from './attachments/AttachmentButton'
import {AttachmentDropzone} from './attachments/AttachmentDropzone'
import {AttachmentPreviewOutlet} from './attachments/AttachmentPreviewOutlet'
import {useChatAttachments} from './attachments/AttachmentsProvider'

import styles from './PlaygroundChatInput.module.css'

interface PlaygroundChatInputProps {
  model: ModelState
  position: number
  stopStreamingMessages: () => void
  sendMessage: (message: string, attachments: string[]) => void
}

export function PlaygroundChatInput({model, position, stopStreamingMessages, sendMessage}: PlaygroundChatInputProps) {
  const manager = usePlaygroundManager()
  const state = usePlaygroundState()

  const {chatInput, isLoading, chatClosed} = model
  const isSendingMessage = state.models.some(m => m.isLoading)

  const supportsAttachments = useImageAttachmentSupported(model.catalogData)
  const attachmentDisabled = reachedMaxAttachments(model.messages, model.modelInputSchema)
  const canAddAnotherImage = supportsAttachments && !attachmentDisabled

  const [chatAttachments, chatAttachmentsApi] = useChatAttachments()

  const MIN_HEIGHT = 44
  const MAX_HEIGHT = 300

  const text: string = textFromMessageContent(chatInput)
  const setText = useCallback(
    (newText: string) => {
      for (const [index] of state.models.entries()) {
        if (state.syncInputs || index === position) {
          manager.setChatInput(index, newText)
        }
      }
    },
    [manager, position, state.models, state.syncInputs],
  )

  const textAreaRef = useRef<HTMLTextAreaElement>(null)
  const textAreaScrollContainer = useRef<HTMLDivElement>(null)

  const supportsImageOnly = supportImageWithoutText(model.catalogData.name)
  const hasImages = chatAttachments.attachments.length > 0
  const hasInput = text.trim().length > 0
  const canSubmit = hasInput || (hasImages && supportsImageOnly)

  const handleSubmit = async (e?: FormEvent) => {
    e?.preventDefault()

    if (isLoading) return
    if (!canSubmit) return

    const attachments = canAddAnotherImage
      ? await Promise.all(chatAttachments.attachments.map(attachment => attachment.base64URI))
      : []

    sendMessage(text, attachments)
    setText('')
    chatAttachmentsApi.reset()
  }

  const handleInput = useCallback(
    (e: FormEvent<HTMLTextAreaElement>) => {
      setText((e.target as HTMLTextAreaElement).value)
    },
    [setText],
  )

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.key === 'Escape') {
      e.preventDefault()
      stopStreamingMessages()
    }

    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    else if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.nativeEvent.isComposing) {
      e.preventDefault()
      await handleSubmit()
    }
  }

  useLayoutEffect(() => {
    let tries = 0

    function adjustHeight() {
      if (!textAreaRef.current || !textAreaScrollContainer.current) return

      const currentScrollPosition = textAreaScrollContainer.current.scrollTop

      tries++
      if (textAreaRef.current.scrollHeight === 0 && tries < 10) {
        // because this is (often) in a Portal, useLayoutEffect() can run before we're inserted in the DOM, and we are
        // thus unable to get a correct scrollHeight. in that case, let's try again in a bit
        // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
        setTimeout(adjustHeight, 1)
      }

      textAreaRef.current.style.height = '0'
      const scrollHeight = textAreaRef.current.scrollHeight
      const containerHeight = Math.min(scrollHeight, MAX_HEIGHT)

      // textareaPreviewRef.current.style.height = `${scrollHeight}px`
      textAreaRef.current.style.height = `${scrollHeight}px`
      textAreaScrollContainer.current.style.height = `${containerHeight}px`
      textAreaScrollContainer.current.scrollTop = currentScrollPosition
    }

    adjustHeight()
  }, [text, textAreaRef])

  return (
    <AttachmentDropzone enabled={supportsAttachments && !attachmentDisabled}>
      <Box
        className={styles.root}
        sx={{
          zIndex: 1,
          borderRadius: 'var(--borderRadius-medium)',
          boxShadow: '0 0 0 1px var(--borderColor-default, var(--color-border-default))',
          mr: 3,
        }}
      >
        {supportsAttachments && !attachmentDisabled ? <AttachmentPreviewOutlet /> : null}

        <Box
          className="copilot-chat-input"
          sx={{
            position: 'relative',
            borderRadius: 'var(--borderRadius-medium)',
            display: 'flex',
            alignItems: 'end',
            gap: 2,
            backgroundColor: 'canvas.default',
            px: 2,

            '> div': {flex: 1},

            ':focus-within .copilot-keyboard-shortcuts': {
              opacity: 1,
              visibility: 'visible',
            },

            ':has(textarea:focus)': {
              boxShadow: '0 0 0 2px var(--focus-outlineColor, var(--color-accent-emphasis))',
            },
          }}
        >
          <Box
            as="form"
            sx={{
              display: 'flex',
              alignItems: 'end',
              flexGrow: 1,
              '.copilot-chat-textarea::placeholder': {userSelect: 'none'},
            }}
            onSubmit={handleSubmit}
          >
            <Box
              ref={textAreaScrollContainer}
              className="copilot-chat-textarea-scroll-container"
              sx={{
                maxHeight: '30dvh',
                minHeight: `${MIN_HEIGHT}px`,
                overflowY: 'auto',
                position: 'relative',
                '> div:first-child': {position: 'static'},
                flexGrow: 1,
              }}
            >
              <Textarea
                // id={copilotChatTextAreaId}
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
                disabled={chatClosed}
                // onScroll={synchronizeScroll}
                onInput={handleInput}
                aria-label="Prompt"
                placeholder="Type your prompt…"
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
                    background: 'transparent',
                    caretColor: 'var(--fgColor-default, var(--color-fg-default))',
                    overflowY: 'hidden',
                    px: 2,
                    py: '12px',
                    verticalAlign: 'middle',
                    resize: 'none',
                    zIndex: 1,
                  },
                  ':focus-within': {
                    boxShadow: 'none',
                  },
                }}
              />
            </Box>

            <span className="mb-2">
              {isLoading ? (
                <IconButtonWithTooltip
                  variant="invisible"
                  size="small"
                  onClick={stopStreamingMessages}
                  icon={SquareFillIcon}
                  label="Stop"
                  tooltipDirection="w"
                />
              ) : (
                <div className="d-flex flex-items-center gap-2">
                  {supportsAttachments ? <AttachmentButton disabled={attachmentDisabled} /> : null}

                  <IconButtonWithTooltip
                    variant="invisible"
                    size="small"
                    onClick={handleSubmit}
                    icon={PaperAirplaneIcon}
                    disabled={!canSubmit || isSendingMessage || chatClosed}
                    label="Send now"
                    tooltipDirection="w"
                  />
                </div>
              )}
            </span>
          </Box>
        </Box>
      </Box>
    </AttachmentDropzone>
  )
}
