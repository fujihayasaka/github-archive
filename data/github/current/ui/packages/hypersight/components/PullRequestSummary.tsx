import {BranchName, Link} from '@primer/react'
import {userHovercardPath} from '@github-ui/paths'
import type {PullRequest} from '../utils/types'
import styles from './PullRequestSummary.module.css'

interface PullRequestSummaryProps {
  pullRequest: PullRequest
}

export function PullRequestSummary({pullRequest}: PullRequestSummaryProps) {
  return (
    <div className="px-3 pt-4">
      <h1 className="gh-header-title mb-2 lh-condensed f1 mr-0 flex-auto wb-break-word">
        {pullRequest.title}
        <span className="f1-light color-fg-muted">
          {' #'}
          {pullRequest.number}
        </span>
      </h1>
      <p>
        <Link
          data-hovercard-url={userHovercardPath({owner: pullRequest.user.login})}
          href={`/${pullRequest.user.login}`}
          className={styles.author}
        >
          {pullRequest.user.login}
        </Link>
        {' wants to merge '}
        {pullRequest.commits}
        <span>{pullRequest.commits > 1 ? ' commits into ' : ' commit into '}</span>
        <BranchName>{pullRequest.base.ref}</BranchName>
        {' from '}
        <BranchName>{pullRequest.base.repo.owner.login}</BranchName>
      </p>
    </div>
  )
}
