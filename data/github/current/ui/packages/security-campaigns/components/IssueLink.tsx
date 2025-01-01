import {LinkButton} from '@primer/react'
import type {Issue} from '../types/issue'
import {issueHovercardPath, issuePath} from '@github-ui/paths'
import {IssueOpenedIcon, SkipIcon, CheckCircleIcon} from '@primer/octicons-react'
import {LABELS} from '@github-ui/issue-viewer/Labels'

export type IssueLinkProps = {
  issue: Issue
}

export function IssueLink({issue}: IssueLinkProps) {
  const getIssueIcon = (state: string, stateReason: string | null) => {
    if (state === 'open') {
      return <IssueOpenedIcon className={'fgColor-open'} />
    } else {
      if (stateReason === 'not_planned' || stateReason === 'duplicate') {
        return <SkipIcon className={'fgColor-muted'} />
      }
      return <CheckCircleIcon className={'fgColor-done'} />
    }
  }

  return (
    <LinkButton
      className="px-2 mx-1"
      variant="invisible"
      href={issuePath({
        owner: issue.owner,
        repo: issue.repo,
        issueNumber: issue.number,
      })}
      data-hovercard-url={issueHovercardPath({
        owner: issue.owner,
        repo: issue.repo,
        issueNumber: issue.number,
      })}
    >
      {getIssueIcon(issue.state, issue.stateReason)} {LABELS.issueNumber(issue.number)}
    </LinkButton>
  )
}
