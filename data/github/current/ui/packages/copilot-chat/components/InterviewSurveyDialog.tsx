import {Button, Dialog, LinkButton} from '@primer/react'
import {forwardRef, useImperativeHandle, useState} from 'react'

import styles from './InterviewSurveyDialog.module.css'

const imageSrc = '/images/modules/copilot-chat/mona-copilot-hubot-spaceship.png'
const imageSrc2x = '/images/modules/copilot-chat/mona-copilot-hubot-spaceship@2x.png'

type InterviewSurveyDialogProps = {
  /**
   * Optional title for the dialog.
   * The default is 'Give feedback'.
   */
  title?: string
  onClose?: (reason: 'close' | 'no-thanks') => void
}

export interface DialogRef {
  openDialog: () => void
}

function InterviewSurveyDialogInner(
  {title = 'Give feedback', onClose}: InterviewSurveyDialogProps,
  ref: React.ForwardedRef<DialogRef>,
) {
  const [isOpen, setIsOpen] = useState(false)

  useImperativeHandle(ref, () => ({
    openDialog: () => setIsOpen(true),
  }))

  const handleClose = (reason: 'close' | 'no-thanks') => {
    setIsOpen(false)
    onClose?.(reason)
  }

  const renderBody = () => (
    <div className={styles.body}>
      <img alt="Mona and Copilot flying a Hubot-themed spaceship" src={imageSrc} srcSet={`${imageSrc2x} 2x`} />
      <span className={styles.primaryText}>Would you like to participate in our research?</span>
      <span className={styles.secondaryText}>You will be compensated for your time</span>
      <LinkButton
        variant="primary"
        className={styles.surveyLink}
        href={'/github-copilot/chat/feedback/interview-survey'}
        target="_blank"
      >
        Book a session
      </LinkButton>
      <Button variant="link" className={styles.noThanksButton} onClick={() => handleClose('no-thanks')}>
        No, thanks
      </Button>
    </div>
  )

  return (
    isOpen && (
      <Dialog className={styles.dialog} onClose={() => handleClose('close')} title={title} renderBody={renderBody} />
    )
  )
}

export const InterviewSurveyDialog = forwardRef(InterviewSurveyDialogInner)
