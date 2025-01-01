import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useMemo, useState} from 'react'
import {NegativeFeedbackButton, PositiveFeedbackButton} from './Buttons'
import type {FeedbackOptions, FeedbackSubmitHandler} from './types'

export interface CopilotCodeReviewFeedbackProps {
  commentId: string
  commentUrl?: string
  feedbackPath?: string
  feedbackOptions?: FeedbackOptions
  additionalParameters?: Record<string, string>
}

const Feedback: React.FC<CopilotCodeReviewFeedbackProps> = ({
  commentId,
  commentUrl,
  feedbackPath,
  feedbackOptions,
  additionalParameters,
}) => {
  const [typeSubmitted, setTypeSubmitted] = useState<'POSITIVE' | 'NEGATIVE'>()

  const path = useMemo(() => {
    if (feedbackPath) return feedbackPath
    if (commentUrl) {
      const parsedPath = new URL(commentUrl, ssrSafeLocation.origin)
      parsedPath.hash = ''
      return `${parsedPath}/code_review_feedback`
    }

    throw new Error('missing feedbackPath and commentUrl')
  }, [commentUrl, feedbackPath])

  const handleClick: FeedbackSubmitHandler = (type, feedbackChoice, textResponse) => {
    setTypeSubmitted(type)
    try {
      const body = new FormData()
      body.set('comment_id', commentId)
      body.set('feedback', type)
      if (additionalParameters) {
        for (const [key, value] of Object.entries(additionalParameters)) {
          body.set(key, value)
        }
      }
      for (const choice of feedbackChoice ?? []) body.append('feedback_choice[]', choice)
      if (textResponse) body.set('text_response', textResponse)
      verifiedFetch(path, {method: 'POST', body})
    } catch {
      // nothing users can really do here, so just fail silently
    }
  }

  return (
    <div data-testid={`copilot-code-review-feedback-${commentId}`} className="d-flex gap-1">
      {typeSubmitted !== 'NEGATIVE' && <PositiveFeedbackButton disabled={!!typeSubmitted} onClick={handleClick} />}
      {typeSubmitted !== 'POSITIVE' && (
        <NegativeFeedbackButton disabled={!!typeSubmitted} onClick={handleClick} feedbackOptions={feedbackOptions} />
      )}
    </div>
  )
}

export const CopilotCodeReviewFeedback: React.FC<CopilotCodeReviewFeedbackProps> = props => (
  <ErrorBoundary fallback={null}>
    <Feedback {...props} />
  </ErrorBoundary>
)
