import type React from 'react'
import {useState, forwardRef, useImperativeHandle} from 'react'
import {Textarea, FormControl, Button, Link} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import styles from './UserFeedback.module.css'
import {clsx} from 'clsx'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

type RatingOption = {
  label: string
  icon: React.ReactNode
  description: string
  value: number
}

export interface FeedbackRef {
  openDialog: () => void
}

type UserFeedbackEvent = {
  subject: string
  rating: number
  content?: string
  hostname: string
  path?: string
}

type UserFeedbackProps = {}

export const UserFeedback = forwardRef<FeedbackRef, UserFeedbackProps>((props, ref) => {
  const [selectedRating, setSelectedRating] = useState<number | null>(null)
  const [selectedCategory, setSelectedCategory] = useState<string>('specific')
  const [feedbackText, setFeedbackText] = useState<string>('')
  const [errors, setErrors] = useState<string[]>([])
  const [isOpen, setIsOpen] = useState(false)

  useImperativeHandle(ref, () => ({
    openDialog: () => setIsOpen(true),
  }))

  const resetForm = () => {
    setSelectedRating(null)
    setSelectedCategory('specific')
    setFeedbackText('')
    setErrors([])
  }

  const feedbackRoute = '/github-copilot/feedback'

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    const newErrors = []
    if (!selectedRating) {
      newErrors.push('Please select a rating.')
    }

    if (feedbackText.length > 2000) {
      newErrors.push('Please keep your feedback under 2000 characters.')
    }

    if (newErrors.length > 0) {
      setErrors(newErrors)
      return
    }

    const body: UserFeedbackEvent = {
      subject: selectedCategory,
      rating: selectedRating,
      content: feedbackText,
      hostname: window.location.hostname,
      path: window.location.pathname,
    } as UserFeedbackEvent

    try {
      const response = await verifiedFetchJSON(feedbackRoute, {
        method: 'POST',
        body,
      })
      if (!response.ok) {
        setErrors(['An error occurred while submitting your feedback.'])
        return
      }
    } catch {
      setErrors(['An error occurred while submitting your feedback.'])
      return
    }

    resetForm()
    setIsOpen(false)
  }

  const handleDialogClose = () => {
    resetForm()
    setIsOpen(false)
  }

  const handleRatingSelect = (rating: number) => {
    setSelectedRating(rating)
    setErrors(prevErrors => prevErrors.filter(error => error !== 'An error occurred while submitting your feedback.'))
  }

  const handleFeedbackChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setFeedbackText(e.target.value)
    setErrors(prevErrors => prevErrors.filter(error => error !== 'An error occurred while submitting your feedback.'))
  }

  const reactionMap: RatingOption[] = [
    {
      label: 'verySatisfied',
      icon: (
        <svg
          width="16"
          aria-hidden="true"
          height="16"
          viewBox="0 0 16 16"
          fill="currentColor"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M5.65646 10.3C6.15313 11.1452 7.09616 11.7 8 11.7C8.47794 11.7 9.0345 11.4947 9.54632 11.0854C9.83116 10.8576 10.0753 10.5876 10.2645 10.3H5.65646ZM11.8447 9.98403C11.3379 11.6073 9.66897 13 8 13C6.30092 13 4.60185 11.7628 4.12902 9.98904C3.98676 9.45539 4.44771 9 5 9H11C11.5523 9 12.0093 9.45684 11.8447 9.98403Z"
          />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M8 14.5C11.5899 14.5 14.5 11.5899 14.5 8C14.5 4.41015 11.5899 1.5 8 1.5C4.41015 1.5 1.5 4.41015 1.5 8C1.5 11.5899 4.41015 14.5 8 14.5ZM8 16C12.4183 16 16 12.4183 16 8C16 3.58172 12.4183 0 8 0C3.58172 0 0 3.58172 0 8C0 12.4183 3.58172 16 8 16Z"
          />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M11.3292 6.83541C10.9875 6.15213 10.0125 6.15213 9.67082 6.83541C9.48558 7.20589 9.03507 7.35606 8.66459 7.17082C8.29411 6.98558 8.14394 6.53507 8.32918 6.16459C9.22361 4.37574 11.7764 4.37574 12.6708 6.16459C12.8561 6.53507 12.7059 6.98558 12.3354 7.17082C11.9649 7.35606 11.5144 7.20589 11.3292 6.83541Z"
          />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M6.32918 6.83541C5.98754 6.15213 5.01246 6.15213 4.67082 6.83541C4.48558 7.20589 4.03507 7.35606 3.66459 7.17082C3.29411 6.98558 3.14394 6.53507 3.32918 6.16459C4.22361 4.37574 6.77639 4.37574 7.67082 6.16459C7.85606 6.53507 7.70589 6.98558 7.33541 7.17082C6.96493 7.35606 6.51442 7.20589 6.32918 6.83541Z"
          />
        </svg>
      ),
      description: 'Love it',
      value: 4,
    },
    {
      label: 'satisfied',
      icon: (
        <svg
          width="16"
          aria-hidden="true"
          height="16"
          viewBox="0 0 16 16"
          fill="currentColor"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M8 14.5C11.5899 14.5 14.5 11.5899 14.5 8C14.5 4.41015 11.5899 1.5 8 1.5C4.41015 1.5 1.5 4.41015 1.5 8C1.5 11.5899 4.41015 14.5 8 14.5ZM8 16C12.4183 16 16 12.4183 16 8C16 3.58172 12.4183 0 8 0C3.58172 0 0 3.58172 0 8C0 12.4183 3.58172 16 8 16Z"
          />
          <path d="M6.5 6.5C6.5 7.05228 6.05228 7.5 5.5 7.5C4.94772 7.5 4.5 7.05228 4.5 6.5C4.5 5.94772 4.94772 5.5 5.5 5.5C6.05228 5.5 6.5 5.94772 6.5 6.5Z" />
          <path d="M11.5 6.5C11.5 7.05228 11.0523 7.5 10.5 7.5C9.94772 7.5 9.5 7.05228 9.5 6.5C9.5 5.94772 9.94772 5.5 10.5 5.5C11.0523 5.5 11.5 5.94772 11.5 6.5Z" />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M10.3569 9.61413C9.28933 11.3934 6.71067 11.3934 5.64312 9.61413C5.43001 9.25894 4.96931 9.14377 4.61413 9.35688C4.25894 9.56999 4.14377 10.0307 4.35688 10.3859C6.00704 13.1361 9.99296 13.1361 11.6431 10.3859C11.8562 10.0307 11.7411 9.56999 11.3859 9.35688C11.0307 9.14377 10.57 9.25894 10.3569 9.61413Z"
          />
        </svg>
      ),
      description: 'It’s ok',
      value: 3,
    },
    {
      label: 'dissatisfied',
      icon: (
        <svg
          width="16"
          height="16"
          aria-hidden="true"
          viewBox="0 0 16 16"
          fill="currentColor"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M8 14.5C11.5899 14.5 14.5 11.5899 14.5 8C14.5 4.41015 11.5899 1.5 8 1.5C4.41015 1.5 1.5 4.41015 1.5 8C1.5 11.5899 4.41015 14.5 8 14.5ZM8 16C12.4183 16 16 12.4183 16 8C16 3.58172 12.4183 0 8 0C3.58172 0 0 3.58172 0 8C0 12.4183 3.58172 16 8 16Z"
          />
          <path d="M6.5 6.5C6.5 7.05228 6.05228 7.5 5.5 7.5C4.94772 7.5 4.5 7.05228 4.5 6.5C4.5 5.94772 4.94772 5.5 5.5 5.5C6.05228 5.5 6.5 5.94772 6.5 6.5Z" />
          <path d="M11.5 6.5C11.5 7.05228 11.0523 7.5 10.5 7.5C9.94772 7.5 9.5 7.05228 9.5 6.5C9.5 5.94772 9.94772 5.5 10.5 5.5C11.0523 5.5 11.5 5.94772 11.5 6.5Z" />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M10.3416 11.8591C9.33064 10.0058 6.66936 10.0058 5.65842 11.8591C5.46007 12.2228 5.0045 12.3568 4.64086 12.1584C4.27722 11.9601 4.14323 11.5045 4.34158 11.1409C5.92104 8.24518 10.079 8.24518 11.6584 11.1409C11.8568 11.5045 11.7228 11.9601 11.3591 12.1584C10.9955 12.3568 10.5399 12.2228 10.3416 11.8591Z"
          />
        </svg>
      ),
      description: 'Not great',
      value: 2,
    },
    {
      label: 'veryDissatisfied',
      icon: (
        <svg
          width="16"
          height="16"
          aria-hidden="true"
          viewBox="0 0 16 16"
          fill="currentColor"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M8 14.5C11.5899 14.5 14.5 11.5899 14.5 8C14.5 4.41015 11.5899 1.5 8 1.5C4.41015 1.5 1.5 4.41015 1.5 8C1.5 11.5899 4.41015 14.5 8 14.5ZM8 16C12.4183 16 16 12.4183 16 8C16 3.58172 12.4183 0 8 0C3.58172 0 0 3.58172 0 8C0 12.4183 3.58172 16 8 16Z"
          />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M5.65646 10.7C6.15313 9.85483 7.09616 9.3 8 9.3C8.47794 9.3 9.0345 9.50535 9.54632 9.9146C9.83116 10.1424 10.0753 10.4124 10.2645 10.7H5.65646ZM11.8447 11.016C11.3379 9.39273 9.66897 8 8 8C6.30092 8 4.60185 9.23723 4.12902 11.011C3.98676 11.5446 4.44771 12 5 12H11C11.5523 12 12.0093 11.5432 11.8447 11.016Z"
          />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M3.89649 4.7586C4.02981 4.42529 4.40809 4.26317 4.7414 4.39649L7.00928 5.30364C7.63789 5.55509 7.6379 6.44491 7.00928 6.69636L4.7414 7.60351C4.40809 7.73683 4.02981 7.57471 3.89649 7.2414C3.76317 6.90809 3.92529 6.52981 4.2586 6.39649L5.24982 6L4.2586 5.60351C3.92529 5.47019 3.76317 5.09191 3.89649 4.7586Z"
          />
          <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M12.1035 4.7586C11.9702 4.42529 11.5919 4.26317 11.2586 4.39649L8.99072 5.30364C8.36211 5.55509 8.3621 6.44491 8.99072 6.69636L11.2586 7.60351C11.5919 7.73683 11.9702 7.57471 12.1035 7.2414C12.2368 6.90809 12.0747 6.52981 11.7414 6.39649L10.7502 6L11.7414 5.60351C12.0747 5.47019 12.2368 5.09191 12.1035 4.7586Z"
          />
        </svg>
      ),
      description: 'Hate it',
      value: 1,
    },
  ]

  const renderBody = () => (
    <div className={styles.bodyContainer}>
      <FormControl required>
        <FormControl.Label visuallyHidden>Rating</FormControl.Label>
        <div className={styles.ratingContainer}>
          {reactionMap.map(rating => (
            <div key={rating.description} className={styles.ratingOption}>
              <button
                type="button"
                role="radio"
                aria-label={rating.description}
                aria-checked={selectedRating === rating.value}
                onClick={() => handleRatingSelect(rating.value)}
                className={clsx(styles.ratingButton, styles[rating.label as keyof typeof styles])}
              >
                {rating.icon}
              </button>
              <span className={styles.ratingCaption}>{rating.description}</span>
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
              <span key={error}>{error}</span>
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
          title="Rate your experience"
          renderBody={renderBody}
          renderFooter={renderFooter}
          sx={{width: '400px'}}
        />
      )}
    </>
  )
})

UserFeedback.displayName = 'UserFeedback'
