import {graphql, useFragment} from 'react-relay'
import {Link, Token} from '@primer/react'
import type {HeaderBlockedBySummary$key} from './__generated__/HeaderBlockedBySummary.graphql'
import {BlockedIcon} from '@primer/octicons-react'
import styles from './HeaderBlockedBySummary.module.css'
import {issueHovercardPath} from '@github-ui/paths'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import dividerLineStyles from './HeaderMetadataDivider.module.css'

export type HeaderBlockedBySummaryProps = {
  blockedBySecondaryKey?: HeaderBlockedBySummary$key
  size?: 'xlarge' | 'small'
}

export const HeaderBlockedBySummary = ({blockedBySecondaryKey, size = 'xlarge'}: HeaderBlockedBySummaryProps) => {
  const node = useFragment(
    graphql`
      fragment HeaderBlockedBySummary on Issue {
        state
        issueDependenciesSummary {
          blockedBy
        }
        blockedBy(first: 1, ranked: true) {
          nodes {
            title
            number
            url
            repository {
              name
              owner {
                login
              }
            }
          }
        }
      }
    `,
    blockedBySecondaryKey,
  )

  const {blockedBy: blockedByCount} = node?.issueDependenciesSummary ?? {}
  if (!node || !blockedByCount) return <></>
  if (node.state === 'CLOSED') return <></>

  const blockedByIssue = blockedByCount === 1 ? node?.blockedBy?.nodes?.[0] || undefined : undefined
  return (
    <>
      {size !== 'small' && <span className={dividerLineStyles.dividerLine} />}
      <HeaderBlockedBySummaryInternal blockedByCount={blockedByCount} size={size} blockedByIssue={blockedByIssue} />
    </>
  )
}

export type HeaderBlockedBySummaryInternalProps = {
  blockedByCount: number
  size: 'xlarge' | 'small'
  blockedByIssue?: {
    title: string
    number: number
    url: string
    repository: {
      name: string
      owner: {
        login: string
      }
    }
  }
}

export function HeaderBlockedBySummaryInternal({
  blockedByCount,
  size,
  blockedByIssue,
}: HeaderBlockedBySummaryInternalProps) {
  const label = `Blocked by ${blockedByCount} issue${blockedByCount === 1 ? '' : 's'}`

  let blockedByIssueLink
  if (blockedByIssue) {
    const {title, number, url, repository} = blockedByIssue
    blockedByIssueLink = (
      <Link
        className={styles.issueLink}
        aria-label={`Blocked by issue ${title}`}
        inline
        muted
        href={url}
        data-hovercard-url={issueHovercardPath({
          owner: repository.owner.login,
          repo: repository.name,
          issueNumber: number,
        })}
      >
        {size === 'small' ? `#${number}` : <SafeHTMLText html={title as SafeHTMLString} className="markdown-title" />}
      </Link>
    )
  }

  if (size === 'small') {
    return (
      <div className={styles.smallSummary}>
        <BlockedIcon className="fgColor-danger" size={14} />
        <span className={styles.visualLabel}>{blockedByIssueLink || blockedByCount}</span>
        <span className="sr-only">{label}</span>
      </div>
    )
  }

  const leadingText = `Blocked by${blockedByIssueLink ? ':' : ''}`
  return (
    <Token
      text={
        <>
          <span className={styles.visualLabel}>
            {leadingText} {blockedByIssueLink || blockedByCount}
          </span>
          <span className="sr-only">{label}</span>
        </>
      }
      leadingVisual={() => <BlockedIcon className="fgColor-danger" size={14} />}
      className={styles.token}
      size="xlarge"
    />
  )
}
