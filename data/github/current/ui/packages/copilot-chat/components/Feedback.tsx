import {ThumbsdownIcon, ThumbsupIcon} from '@primer/octicons-react'
import {IconButton, type IconButtonProps} from '@primer/react'
import {useCallback, useRef} from 'react'

import type {CopilotChatMessageFeedback} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {useChatMessage} from './ChatMessageContext'
import {type FeedbackDialogRef, MessageFeedbackDialog} from './MessageFeedbackDialog'

export type FeedbackProps = {
  iconSize: IconButtonProps['size']
}

export function Feedback({iconSize}: FeedbackProps) {
  const {message} = useChatMessage()
  const messageId = message.id
  const threadId = message.threadID
  const manager = useChatManager()
  const dialogRef = useRef<FeedbackDialogRef>(null)
  const submittedFeedbackButtonRef = useRef<HTMLButtonElement>(null)

  const onFeedbackGiven = useCallback(
    (feedbackGiven: CopilotChatMessageFeedback) => {
      manager.handleFeedback(message, feedbackGiven)
    },
    [manager, message],
  )

  const {optedInToUserFeedback} = useChatState()
  const sendFeedback = useCallback(
    (feedbackGiven: CopilotChatMessageFeedback) => {
      void manager.service.sendFeedback({feedback: feedbackGiven, messageId, threadId})
      onFeedbackGiven(feedbackGiven)

      if (optedInToUserFeedback) {
        dialogRef.current?.openDialog(feedbackGiven)
      } else {
        submittedFeedbackButtonRef.current?.focus()
      }
    },
    [manager.service, messageId, threadId, submittedFeedbackButtonRef, onFeedbackGiven, optedInToUserFeedback],
  )

  return (
    <>
      {message.feedback != null ? (
        <IconButton
          ref={submittedFeedbackButtonRef}
          aria-label={`${message.feedback.toLocaleLowerCase()} feedback submitted`}
          icon={message.feedback === 'POSITIVE' ? ThumbsupIcon : ThumbsdownIcon}
          variant="invisible"
          size={iconSize}
          aria-disabled
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
          />
          <IconButton
            icon={ThumbsdownIcon}
            size={iconSize}
            aria-label={'Bad response'}
            onClick={() => sendFeedback('NEGATIVE')}
            variant="invisible"
          />
        </>
      )}
      <MessageFeedbackDialog
        ref={dialogRef}
        messageId={messageId}
        threadId={threadId}
        onSubmitted={onFeedbackGiven}
        returnFocusRef={submittedFeedbackButtonRef}
      />
    </>
  )
}
