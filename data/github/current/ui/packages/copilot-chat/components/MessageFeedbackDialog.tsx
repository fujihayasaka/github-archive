import {type FeedbackRef, type RatingOption, UserFeedback} from '@github-ui/user-feedback'
import {ThumbsdownIcon, ThumbsupIcon} from '@primer/octicons-react'
import {forwardRef, useImperativeHandle, useRef} from 'react'

import type {CopilotChatMessageFeedback} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {type DialogRef, InterviewSurveyDialog} from './InterviewSurveyDialog'
import styles from './MessageFeedbackDialog.module.css'

const ratingOptions: Array<RatingOption<CopilotChatMessageFeedback>> = [
  {
    name: 'Bad',
    value: 'NEGATIVE' as const,
    icon: <ThumbsdownIcon className={styles.thumbsDown} />,
    color: 'bad',
  },
  {
    name: 'Good',
    value: 'POSITIVE' as const,
    icon: <ThumbsupIcon className={styles.thumbsUp} />,
    color: 'good',
  },
]

type Rating = (typeof ratingOptions)[number]['value']
export type FeedbackDialogRef = FeedbackRef<Rating>

type MessageFeedbackDialogProps = {
  messageId: string
  threadId: string
  onSubmitted?: (rating: Rating) => void
  onClose?: () => void
}

export const MessageFeedbackDialog = forwardRef(function (
  {messageId, threadId, onSubmitted, onClose}: MessageFeedbackDialogProps,
  ref: React.ForwardedRef<FeedbackDialogRef>,
) {
  const manager = useChatManager()
  const surveyDialogRef = useRef<DialogRef>(null)
  const feedbackDialogRef = useRef<FeedbackDialogRef>(null)
  const initialRatingRef = useRef<Rating | undefined>(undefined)

  useImperativeHandle(ref, () => ({
    openDialog: (rating?: Rating) => {
      initialRatingRef.current = rating
      if (copilotFeatureFlags.copilotChatInterviewSurvey) {
        surveyDialogRef.current?.openDialog()
      } else {
        feedbackDialogRef.current?.openDialog(rating)
      }
    },
  }))

  const onSubmit = async (rating: Rating | null, text: string): Promise<string[]> => {
    const errors = []

    if (rating == null) {
      errors.push('Please select a rating.')
    }

    // max length based on hydro payload size limit
    // see https://github.com/github/copilot-api/blob/62323cfa4bfc31f808f8a457644f11bb706b8298/pkg/rest/chat.go#L382-L384
    const limit = 500
    if (text.length > limit) {
      errors.push(`Please keep your feedback within ${limit} characters or less.`)
    }

    if (errors.length > 0) {
      return errors
    } else {
      rating = rating! // Make TS happy
    }

    try {
      const response = await manager.service.sendFeedback({
        feedback: rating,
        feedbackChoice: [], // This component does not offer users the ability to choose these (e.g. "UNHELPFUL", "INCORRECT", "NOT_TRUE", "POORLY_FORMATTED", etc.)
        messageId,
        threadId,
        textResponse: text,
      })

      if (response.ok) {
        onSubmitted?.(rating)
      } else {
        errors.push('An error occurred while submitting your feedback.')
      }
    } catch {
      errors.push('An error occurred while submitting your feedback.')
    }

    return errors
  }

  const onSurveyClose = (reason: 'close' | 'no-thanks') => {
    if (reason === 'no-thanks') {
      feedbackDialogRef.current?.openDialog(initialRatingRef.current)
    } else {
      onClose?.()
    }
  }

  return (
    <>
      <InterviewSurveyDialog ref={surveyDialogRef} title="Give additional feedback" onClose={onSurveyClose} />
      <UserFeedback
        title="Give additional feedback"
        ref={feedbackDialogRef}
        options={ratingOptions}
        onSubmit={onSubmit}
        onClose={onClose}
      />
    </>
  )
})

MessageFeedbackDialog.displayName = 'MessageFeedbackDialog'
