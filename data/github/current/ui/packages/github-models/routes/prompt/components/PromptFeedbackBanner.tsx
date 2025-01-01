import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import styles from './PromptFeedbackBanner.module.css'
import {feedbackUrl} from '../../../constants'

const bookACallUrl = 'https://gh.io/models-prompt-editor-feedback'

export type PromptFeedbackBannerProps = {
  onDismiss: () => void
}

export function PromptFeedbackBanner({onDismiss}: PromptFeedbackBannerProps) {
  return (
    <Banner
      className={styles.feedbackBanner}
      title="Talk to us"
      hideTitle
      onDismiss={onDismiss}
      primaryAction={
        <Banner.PrimaryAction as={Link} muted href={bookACallUrl} target="_blank" rel="noreferrer">
          Book a call
        </Banner.PrimaryAction>
      }
    >
      <Banner.Description>
        We want to make this new experience amazing for you! Got feedback? Book a call or&nbsp;
        <Link inline href={feedbackUrl}>
          share your thoughts
        </Link>
        .
      </Banner.Description>
    </Banner>
  )
}
