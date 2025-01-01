import {IssueClosedIcon, IssueDraftIcon, IssueOpenedIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps, Truncate} from '@primer/react'
import {clsx} from 'clsx'

import type {AutocompleteIssue} from '../../utils/copilot-chat-types'
import sharedStyles from './shared.module.css'

interface IssueSuggestionProps extends ActionListItemProps {
  issue: AutocompleteIssue
  stale?: boolean
}

export function IssueSuggestion({issue, stale, className, ...props}: IssueSuggestionProps) {
  return (
    <ActionList.Item {...props} className={clsx(sharedStyles.asyncSuggestion, stale && sharedStyles.stale, className)}>
      <ActionList.LeadingVisual>
        {issue.state === 'draft' && <IssueDraftIcon className="fgColor-neutral" />}
        {issue.state === 'open' && <IssueOpenedIcon className="fgColor-open" />}
        {issue.state === 'closed' && <IssueClosedIcon className="fgColor-done" />}
      </ActionList.LeadingVisual>
      <Truncate title={issue.title} maxWidth={350}>
        {issue.title}
      </Truncate>
      <ActionList.Description>#{issue.number}</ActionList.Description>
    </ActionList.Item>
  )
}
