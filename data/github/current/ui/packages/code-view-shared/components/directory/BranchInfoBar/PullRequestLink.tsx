import type {Repository} from '@github-ui/current-repository'
import {pullRequestPath} from '@github-ui/paths'
import {GitPullRequestIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'

import styles from './PullRequestLink.module.css'

interface Props {
  repo: Repository
  pullRequestNumber: number
}

export function PullRequestLink({repo, pullRequestNumber}: Props) {
  return (
    <Link href={pullRequestPath({repo, number: pullRequestNumber})} className={styles.Link}>
      <GitPullRequestIcon size={16} />#{pullRequestNumber}
    </Link>
  )
}
