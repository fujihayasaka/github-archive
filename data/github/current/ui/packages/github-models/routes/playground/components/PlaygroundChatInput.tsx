import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {PaperAirplaneIcon, SquareFillIcon} from '@primer/octicons-react'
import {Textarea} from '@primer/react'
import {useCallback, useRef, type FormEvent} from 'react'
import type {ModelState} from '../../../types'
import {
  reachedMaxAttachments,
  supportImageWithoutText,
  useImageAttachmentSupported,
} from '../../../utils/image-validation'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import {usePlaygroundManager} from '../../../contexts/PlaygroundManagerContext'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {AttachmentButton} from './attachments/AttachmentButton'
import {AttachmentDropzone} from './attachments/AttachmentDropzone'
import {AttachmentPreviewOutlet} from './attachments/AttachmentPreviewOutlet'
import {useAttachments} from '@github-ui/attachments'

import styles from './PlaygroundChatInput.module.css'
import {ImprovePrompt} from './ImprovePrompt'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {clsx} from 'clsx'

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

  const [chatAttachments, chatAttachmentsApi] = useAttachments()

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
  const isFeatureFlagEnabled = useFeatureFlag('github_models_improve_user_prompt')

  const handleSubmit = async (e?: FormEvent) => {
    e?.preventDefault()

    if (isLoading) return
    if (!canSubmit) return

    const attachments = canAddAnotherImage
      ? await Promise.all(chatAttachments.attachments.map(attachment => attachment.url()))
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
      <div className={styles.root}>
        {supportsAttachments && !attachmentDisabled ? <AttachmentPreviewOutlet /> : null}

        <div className={clsx('copilot-chat-input', styles.input)}>
          <form className={styles.form} onSubmit={handleSubmit}>
            <div ref={textAreaScrollContainer} className={styles.formContainer}>
              <Textarea
                data-hpc
                className={clsx('copilot-chat-textarea', styles.textarea)}
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
                onInput={handleInput}
                aria-label="Prompt"
                placeholder="Type your prompt…"
                value={text}
              />
            </div>

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
                  {isFeatureFlagEnabled && <ImprovePrompt prompt={text} handleUpdatePrompt={setText} type="user" />}
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
          </form>
        </div>
      </div>
    </AttachmentDropzone>
  )
}
