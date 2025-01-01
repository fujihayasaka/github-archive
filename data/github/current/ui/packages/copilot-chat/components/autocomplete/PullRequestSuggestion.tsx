import {GitPullRequestClosedIcon, GitPullRequestDraftIcon, GitPullRequestIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps, Truncate} from '@primer/react'
import {clsx} from 'clsx'

import type {AutocompletePullRequest} from '../../utils/copilot-chat-types'
import sharedStyles from './shared.module.css'

interface PullRequestSuggestionProps extends ActionListItemProps {
  pullRequest: AutocompletePullRequest
  stale?: boolean
}

export function PullRequestSuggestion({pullRequest, stale, className, ...props}: PullRequestSuggestionProps) {
  return (
    <ActionList.Item {...props} className={clsx(sharedStyles.asyncSuggestion, stale && sharedStyles.stale, className)}>
      <ActionList.LeadingVisual>
        {pullRequest.state === 'draft' && <GitPullRequestDraftIcon className="fgColor-neutral" />}
        {pullRequest.state === 'open' && <GitPullRequestIcon className="fgColor-open" />}
        {pullRequest.state === 'closed' && <GitPullRequestClosedIcon className="fgColor-done" />}
      </ActionList.LeadingVisual>
      <Truncate title={pullRequest.title} maxWidth={350}>
        {pullRequest.title}
      </Truncate>
      <ActionList.Description>#{pullRequest.number}</ActionList.Description>
    </ActionList.Item>
  )
}
