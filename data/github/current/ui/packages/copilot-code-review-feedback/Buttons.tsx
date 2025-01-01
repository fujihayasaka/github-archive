import {ThumbsdownIcon, ThumbsupIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useRef, useState} from 'react'
import {NegativeFeedbackForm} from './NegativeFeedbackForm'
import type {FeedbackSubmitHandler, FeedbackOptions} from './types'

interface PositiveFeedbackButtonProps {
  disabled: boolean
  onClick: FeedbackSubmitHandler
}

export const PositiveFeedbackButton: React.FC<PositiveFeedbackButtonProps> = ({onClick, disabled}) => (
  <IconButton
    size="small"
    variant="invisible"
    disabled={disabled}
    icon={ThumbsupIcon}
    title="Positive Feedback"
    aria-label="Positive Feedback"
    onClick={() => onClick('POSITIVE')}
  />
)

interface NegativeFeedbackButtonProps {
  disabled: boolean
  onClick: FeedbackSubmitHandler
  feedbackOptions?: FeedbackOptions
}

export const NegativeFeedbackButton: React.FC<NegativeFeedbackButtonProps> = ({onClick, disabled, feedbackOptions}) => {
  const [dialogOpen, setDialogOpen] = useState(false)
  const returnFocusRef = useRef<HTMLButtonElement>(null)

  const handleSubmit: FeedbackSubmitHandler = (type, feedbackChoice, textResponse) => {
    onClick(type, feedbackChoice, textResponse)
    setDialogOpen(false)
  }

  return (
    <>
      {dialogOpen && (
        <NegativeFeedbackForm
          onClose={() => setDialogOpen(false)}
          onSubmit={handleSubmit}
          feedbackOptions={feedbackOptions}
          returnFocusRef={returnFocusRef}
        />
      )}
      <IconButton
        ref={returnFocusRef}
        size="small"
        variant="invisible"
        disabled={disabled}
        icon={ThumbsdownIcon}
        title="Negative Feedback"
        aria-label="Negative Feedback"
        onClick={() => setDialogOpen(true)}
      />
    </>
  )
}
