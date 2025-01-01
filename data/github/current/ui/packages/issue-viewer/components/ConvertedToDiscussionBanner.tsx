import {Text, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import styles from './converted-to-discussion-banner.module.css'
import {ArrowRightIcon, InfoIcon} from '@primer/octicons-react'
import {LABELS} from '../constants/labels'

type ConvertedToDiscussionBannerProps = {
  discussionUrl: string
}

export const ConvertedToDiscussionBanner = ({discussionUrl}: ConvertedToDiscussionBannerProps) => {
  return (
    <div className={styles.bannerContainer}>
      <div className={styles.bannerContent}>
        <Octicon icon={InfoIcon} size={16} sx={{color: 'accent.fg', mt: 1}} />
        <div className={styles.textContent}>
          <Text sx={{fontWeight: 'bold'}}>{LABELS.convertToDiscussion.converted}</Text>
          <Link href={discussionUrl} sx={{color: 'accent.fg', display: 'flex', alignItems: 'center', mt: 1}}>
            {LABELS.convertToDiscussion.goToDiscussion}
            <Octicon icon={ArrowRightIcon} size={16} sx={{ml: 1}} />
          </Link>
        </div>
      </div>
    </div>
  )
}
