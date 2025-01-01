import {announceFromElement} from '@github-ui/aria-live'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {FeedbackDialog} from '@github-ui/github-models/FeedbackDialog'
import {sendFeedback} from '@github-ui/github-models/SendFeedback'
import {testIdProps} from '@github-ui/test-id-props'
import {ThumbsdownIcon, ThumbsupIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef, useState} from 'react'
import type {RepoModel} from '../../../types'
import type {Message} from '../types'
import styles from './CompletionMessage.module.css'
import {CompletionError} from './CompletionError'

const Feedback = {
  UNKNOWN: 0,
  POSITIVE: 1,
  NEGATIVE: 2,
} as const
type Feedback = (typeof Feedback)[keyof typeof Feedback]

const FeedbackValue = {
  POSITIVE: 'POSITIVE',
  NEGATIVE: 'NEGATIVE',
} as const
type FeedbackValue = (typeof FeedbackValue)[keyof typeof FeedbackValue]

export type CompletionMessageProps = {
  isLoading: boolean
  isError: boolean
  index: number
  message: Message
  lastIndex: boolean
  model: RepoModel
}

export function CompletionMessage({isLoading, isError, message, index, lastIndex, model}: CompletionMessageProps) {
  const returnFocusRef = useRef(null)
  const messageRef = useRef(null)
  const [submittedFeedback, setSubmittedFeedback] = useState<
    typeof FeedbackValue.POSITIVE | typeof FeedbackValue.NEGATIVE | undefined
  >(undefined)

  const positiveFeedbackSubmitted = submittedFeedback === FeedbackValue.POSITIVE
  const [isFeedbackDialogOpen, setIsFeedbackDialogOpen] = useState(false)
  // In order to submit negative feedback, the user must click the thumbs down icon and then click the "Submit feedback" button in a dialog
  const [isNegativeFeedbackConfirmed, setIsNegativeFeedbackConfirmed] = useState(false)

  const isAssistantMessage = message.role === 'assistant' && message.message
  const isLastResponse = isAssistantMessage && lastIndex

  // Heuristic to determine if we're rendering JSON or markdown. We can't actually parse
  // because we're probably halfway through a streamed message
  const isProbablyJSON = (content: string) => content.trim().startsWith('{') || content.trim().startsWith('[')

  useEffect(() => {
    if (!isLoading && lastIndex && messageRef.current) {
      announceFromElement(messageRef.current)
    }
  }, [isLoading, lastIndex])

  const handleSubmit = async () => {
    const feedback = {
      satisfaction: Feedback.POSITIVE,
      reasons: [],
      feedbackText: '',
      contactConsent: false,
      model: model.name,
    }
    try {
      const res = await sendFeedback({model, feedback})
      if (res.ok) {
        setSubmittedFeedback(FeedbackValue.POSITIVE)
      }
    } catch (error) {
      return error
    }
  }

  const handleClick = useCallback(() => {
    setIsFeedbackDialogOpen(true)
    setSubmittedFeedback(FeedbackValue.NEGATIVE)
  }, [])

  if (message.role === 'tool') {
    return null
  }

  // Currently, the content will stream in with one format and is then re-indented at the end
  // This will fall through to the catch for every streamed chunk but the last.
  const wrapInJsonCodeBlock = (content: string) => {
    let formattedContent

    try {
      formattedContent = JSON.stringify(JSON.parse(content.trim()), null, 2)
    } catch {
      formattedContent = content.trim() // Fallback to the original content
    }

    return `\`\`\`json\n${formattedContent}\n\`\`\``
  }

  return (
    <div key={index} className={styles.playgroundChatMessagesContainer} {...testIdProps('completion-chat-message')}>
      {isError ? (
        <CompletionError message={message.message} />
      ) : (
        <div className="position-relative">
          <div className="p-1" dir="auto" ref={messageRef}>
            {isProbablyJSON(message.message) ? (
              <MarkdownRenderer markdown={wrapInJsonCodeBlock(message.message)} />
            ) : (
              <MarkdownRenderer markdown={message.message} />
            )}
          </div>
          {isAssistantMessage && !isLoading && (
            <div className={clsx('message-actions', styles.messageActions, isLastResponse && styles.lastResponse)}>
              {!isNegativeFeedbackConfirmed && (
                <IconButton
                  className={clsx(positiveFeedbackSubmitted ? 'bGcolor-muted' : 'bGcolor-default')}
                  icon={ThumbsupIcon}
                  variant="invisible"
                  aria-label="Positive"
                  onClick={handleSubmit}
                  disabled={positiveFeedbackSubmitted}
                />
              )}
              {submittedFeedback !== FeedbackValue.POSITIVE && (
                <IconButton
                  className={clsx(isNegativeFeedbackConfirmed ? 'bGcolor-muted' : 'bGcolor-default')}
                  icon={ThumbsdownIcon}
                  variant="invisible"
                  aria-label="Negative"
                  onClick={handleClick}
                  disabled={isNegativeFeedbackConfirmed}
                />
              )}
              <CopyToClipboardButton textToCopy={message.message} ariaLabel="Copy to clipboard" />
            </div>
          )}
          {submittedFeedback === FeedbackValue.NEGATIVE && (
            <FeedbackDialog
              isNegativePreSelected
              setIsNegativeFeedbackConfirmed={setIsNegativeFeedbackConfirmed}
              returnFocusRef={returnFocusRef}
              isFeedbackDialogOpen={isFeedbackDialogOpen}
              setIsFeedbackDialogOpen={setIsFeedbackDialogOpen}
              modelName={model.name}
            />
          )}
        </div>
      )}
    </div>
  )
}
