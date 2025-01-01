import {CommentDiscussionIcon, DiscussionClosedIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps, Truncate} from '@primer/react'
import {clsx} from 'clsx'

import type {AutocompleteDiscussion} from '../../utils/copilot-chat-types'
import sharedStyles from './shared.module.css'

interface DiscussionSuggestionProps extends ActionListItemProps {
  discussion: AutocompleteDiscussion
  stale?: boolean
}

export function DiscussionSuggestion({discussion, stale, className, ...props}: DiscussionSuggestionProps) {
  return (
    <ActionList.Item {...props} className={clsx(sharedStyles.asyncSuggestion, stale && sharedStyles.stale, className)}>
      <ActionList.LeadingVisual>
        {discussion.state === 'open' && <CommentDiscussionIcon className="fgColor-open" />}
        {discussion.state === 'closed' && <DiscussionClosedIcon className="fgColor-muted" />}
      </ActionList.LeadingVisual>
      <Truncate title={discussion.title} maxWidth={350}>
        {discussion.title}
      </Truncate>
      <ActionList.Description>#{discussion.number}</ActionList.Description>
    </ActionList.Item>
  )
}
