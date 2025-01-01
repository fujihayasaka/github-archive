import {ThumbsdownIcon, ThumbsupIcon} from '@primer/octicons-react'
import {IconButton, type IconButtonProps} from '@primer/react'
import {useCallback, useMemo, useRef, useState} from 'react'

import type {CopilotChatMessageFeedback} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {useChatMessage} from './ChatMessageContext'
import {type FeedbackDialogRef, MessageFeedbackDialog} from './MessageFeedbackDialog'

export type FeedbackProps = {
  iconSize: IconButtonProps['size']
  returnFocusRef: React.RefObject<HTMLDivElement>
  onFeedbackSubmitted?: () => void
}

export function Feedback({iconSize, returnFocusRef, onFeedbackSubmitted}: FeedbackProps) {
  const {message} = useChatMessage()
  const messageId = message.id
  const threadId = message.threadID
  const manager = useChatManager()
  const [submittedFeedback, setSubmittedFeedback] = useState<CopilotChatMessageFeedback | undefined>(message.feedback)
  const dialogRef = useRef<FeedbackDialogRef>(null)

  const onFeedbackGiven = useCallback(
    (feedbackGiven: CopilotChatMessageFeedback) => {
      if (copilotFeatureFlags.immersiveSubthreading) {
        manager.handleFeedback(message, feedbackGiven)
      } else {
        setSubmittedFeedback(feedbackGiven)
      }

      onFeedbackSubmitted?.()
    },
    [manager, message, onFeedbackSubmitted],
  )

  const feedback = useMemo(() => {
    return copilotFeatureFlags.immersiveSubthreading ? message.feedback : submittedFeedback
  }, [message.feedback, submittedFeedback])

  const onDialogClose = useCallback(() => {
    returnFocusRef.current?.focus()
  }, [returnFocusRef])

  const {optedInToUserFeedback} = useChatState()
  const sendFeedback = useCallback(
    (feedbackGiven: CopilotChatMessageFeedback) => {
      void manager.service.sendFeedback({feedback: feedbackGiven, messageId, threadId})
      onFeedbackGiven(feedbackGiven)

      if (optedInToUserFeedback) {
        dialogRef.current?.openDialog(feedbackGiven)
      } else {
        onDialogClose()
      }
    },
    [manager.service, messageId, threadId, onDialogClose, onFeedbackGiven, optedInToUserFeedback],
  )

  return (
    <>
      {feedback != null ? (
        <IconButton
          aria-label={`${feedback.toLocaleLowerCase()} feedback submitted`}
          icon={feedback === 'POSITIVE' ? ThumbsupIcon : ThumbsdownIcon}
          variant="invisible"
          size={iconSize}
          disabled
          sx={{
            color: 'fg.default',
            bg: 'canvas.subtle',
          }}
        />
      ) : (
        <>
          <IconButton
            icon={ThumbsupIcon}
            aria-label={'Good response'}
            onClick={() => sendFeedback('POSITIVE')}
            variant="invisible"
            size={iconSize}
            className="feedback-action"
          />
          <IconButton
            icon={ThumbsdownIcon}
            size={iconSize}
            aria-label={'Bad response'}
            onClick={() => sendFeedback('NEGATIVE')}
            variant="invisible"
            className="feedback-action"
          />
        </>
      )}
      <MessageFeedbackDialog
        ref={dialogRef}
        messageId={messageId}
        threadId={threadId}
        onSubmitted={onFeedbackGiven}
        onClose={onDialogClose}
      />
    </>
  )
}
