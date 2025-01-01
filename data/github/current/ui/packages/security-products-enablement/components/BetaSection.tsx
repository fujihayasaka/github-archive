import type React from 'react'
import {Label, Link as PrimerLink} from '@primer/react'

import styles from './BetaSection.module.css'

interface feedbackButton {
  showFeedbackLink: boolean
  feedbackLink: string
}

type BetaProps = {
  feedbackButton?: feedbackButton
}

const BetaSection: React.FC<BetaProps> = ({feedbackButton}) => {
  const showFeedbackLink = feedbackButton ? feedbackButton.showFeedbackLink : false
  const feedbackLink = feedbackButton ? feedbackButton.feedbackLink : ''

  return (
    <>
      <Label variant="success" size="small" className="ml-2 v-align-middle">
        Beta
      </Label>
      {showFeedbackLink && (
        <PrimerLink href={feedbackLink} target="_blank" className={styles.PrimerLink}>
          Give feedback
        </PrimerLink>
      )}
    </>
  )
}

export default BetaSection
