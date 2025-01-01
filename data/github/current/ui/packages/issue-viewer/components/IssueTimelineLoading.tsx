import {CommentLoading} from '@github-ui/commenting/CommentLoading'

import {VALUES} from '../constants/values'
import styles from './issue-timeline-loading.module.css'
import {TEST_IDS} from '../constants/test-ids'

type IssueTimelineLoadingProps = {
  rowCount?: number
  delayedShow?: boolean
}

export const IssueTimelineLoading = ({
  rowCount = VALUES.rowLoadingSkeletonCount,
  delayedShow,
}: IssueTimelineLoadingProps) => {
  return (
    <div className={delayedShow ? styles.delaySkeletonLoad : ''} data-testid={TEST_IDS.issueTimelineLoading}>
      {[...Array(rowCount)].map((_, index) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <div key={index}>
          <CommentLoading />
        </div>
      ))}
    </div>
  )
}
