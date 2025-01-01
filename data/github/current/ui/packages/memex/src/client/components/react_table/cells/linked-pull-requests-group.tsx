import type {LinkedPullRequest} from '../../../api/common-contracts'
import {LinkedPullRequestToken} from '../../fields/linked-pr-token'
import {BaseCell} from './base-cell'
import styles from './linked-pull-requests-group.module.css'

interface LinkedPullRequestGroupProps {
  linkedPullRequests: Array<LinkedPullRequest> | undefined
}

export const LinkedPullRequestGroup: React.FC<LinkedPullRequestGroupProps> = ({linkedPullRequests}) => {
  return (
    <BaseCell className={styles.BaseCell}>
      {linkedPullRequests?.map(linkedPullRequest => (
        <LinkedPullRequestToken linkedPullRequest={linkedPullRequest} tabIndex={-1} key={linkedPullRequest.id} />
      ))}
    </BaseCell>
  )
}
