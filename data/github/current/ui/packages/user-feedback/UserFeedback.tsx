import type React from 'react'
import {useState, useImperativeHandle, forwardRef} from 'react'
import {Textarea, FormControl, Button, Link} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import styles from './UserFeedback.module.css'
import colorStyles from './UserFeedbackColors.module.css'
import {clsx} from 'clsx'

export type RatingOption<Value> = {
  name: string
  value: Value
  icon: React.ReactNode
  color: keyof typeof colorStyles
}

export interface FeedbackRef<Value> {
  openDialog: (initialOptionValue?: Value) => void
}

export type UserFeedbackProps<Value> = {
  /**
   * Optional title for the dialog.
   * The default is 'Give feedback'.
   */
  title?: string
  options: Array<RatingOption<Value>>
  /**
   * Called when the user submits the form. Returns an array of errors, which will be displayed to the user.
   * @param ratingValue The value of the selected rating option, or null if no option is selected.
   * @param feedbackText The text of the feedback.
   * @returns An array of errors, which will be displayed to the user.
   */
  onSubmit: (ratingValue: Value | null, feedbackText: string) => Promise<string[]>
  onClose?: () => void
}

function UserFeedbackInner<Value>(
  {title = 'Give feedback', options, onSubmit, onClose}: UserFeedbackProps<Value>,
  ref: React.ForwardedRef<FeedbackRef<Value>>,
) {
  const [selectedRating, setSelectedRating] = useState<Value | null>(null)
  const [feedbackText, setFeedbackText] = useState<string>('')
  const [errors, setErrors] = useState<string[]>([])
  const [isOpen, setIsOpen] = useState(false)

  useImperativeHandle(ref, () => ({
    openDialog: (initialOptionValue?: Value) => {
      if (initialOptionValue != null) {
        if (!options.some(option => option.value === initialOptionValue)) {
          throw new Error('invalid initial option value')
        }

        setSelectedRating(initialOptionValue)
      }
      setIsOpen(true)
    },
  }))

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    let newErrors = []
    try {
      newErrors = await onSubmit(selectedRating, feedbackText)
    } catch {
      newErrors = ['An error occurred while submitting your feedback.']
    }

    setErrors(newErrors)
    if (newErrors.length === 0) {
      handleDialogClose()
    }
  }

  const resetForm = () => {
    setSelectedRating(null)
    setFeedbackText('')
    setErrors([])
  }

  const handleDialogClose = () => {
    resetForm()
    setIsOpen(false)
    onClose?.()
  }

  const handleRatingSelect = (rating: Value) => {
    setSelectedRating(rating)
    setErrors([])
  }

  const handleFeedbackChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setFeedbackText(e.target.value)
    setErrors([])
  }

  const renderBody = () => (
    <div className={styles.bodyContainer}>
      <FormControl required>
        <FormControl.Label visuallyHidden>Rating</FormControl.Label>
        <div className={styles.ratingContainer}>
          {options.map(rating => (
            <div key={rating.name} className={styles.ratingOption}>
              <button
                type="button"
                role="radio"
                aria-label={rating.name}
                aria-checked={selectedRating === rating.value}
                onClick={() => handleRatingSelect(rating.value)}
                className={clsx(styles.ratingButton, colorStyles[rating.color])}
              >
                {rating.icon}
              </button>
              <span className={styles.ratingCaption}>{rating.name}</span>
            </div>
          ))}
        </div>
      </FormControl>
      <div className={styles.messageContainer}>
        <FormControl>
          <FormControl.Label visuallyHidden>Message</FormControl.Label>
          <Textarea
            placeholder="Tell us what you liked or what could be better"
            value={feedbackText}
            onChange={handleFeedbackChange}
            resize="vertical"
            block
            rows={5}
          />
        </FormControl>

        <span className={styles.privacyText}>
          Please don’t include sensitive, confidential, or personal data. Your anonymous feedback helps us improve our
          services in line with our{' '}
          <Link
            href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement"
            inline
            muted
          >
            Privacy Policy
          </Link>
          .
        </span>

        {errors.length > 0 && (
          <div className={styles.validationError}>
            {errors.map(error => (
              <div key={error}>{error}</div>
            ))}
          </div>
        )}
      </div>
    </div>
  )

  const renderFooter = () => (
    <div className={styles.footerContainer}>
      <Button onClick={handleDialogClose}>Cancel</Button>
      <Button variant="primary" type="submit" onClick={handleSubmit}>
        Send
      </Button>
    </div>
  )

  return (
    <>
      {isOpen && (
        <Dialog
          onClose={handleDialogClose}
          title={title}
          renderBody={renderBody}
          renderFooter={renderFooter}
          sx={{width: '400px'}}
        />
      )}
    </>
  )
}

// forwardRef makes the props UserFeedbackProps<unknown> and ref FeedbackRef<unknown>,
// so we need to cast the result to get back our type safety for Value.
export const UserFeedback = forwardRef(UserFeedbackInner) as <Value>(
  props: UserFeedbackProps<Value> & React.RefAttributes<FeedbackRef<Value>>,
) => ReturnType<typeof UserFeedbackInner>
