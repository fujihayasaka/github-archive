import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import {Banner} from '@primer/react/experimental'
import {Button} from '@primer/react'
import {LABELS} from './constants/labels'
import styles from './UserRestrictedView.module.css'

type UserRestrictedViewProps = {
  reasonHTML?: SafeHTMLString | null
  issuesUrl?: string
}

export const UserRestrictedView = ({reasonHTML, issuesUrl}: UserRestrictedViewProps) => {
  return (
    <div className={styles.userRestrictedContainer}>
      {reasonHTML && (
        <Banner aria-label="Warning" variant="warning" hideTitle title="Action restricted">
          <Banner.Description>
            <SafeHTMLText html={reasonHTML} />
          </Banner.Description>
        </Banner>
      )}
      {issuesUrl && (
        <Button as="a" href={issuesUrl} className={styles.backToAllIssuesButton}>
          {LABELS.backToAllIssues}
        </Button>
      )}
    </div>
  )
}
