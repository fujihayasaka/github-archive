import {ActionList} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import type {ParentIssueFragment$key} from './__generated__/ParentIssueFragment.graphql'
import {SubIssuesSummary} from './SubIssuesSummary'
import type React from 'react'
import {useParentIssueSubscription} from '../../ParentIssueSubscription'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import {useIssueState} from '@github-ui/use-issue-state'

const ParentIssueFragment = graphql`
  fragment ParentIssueFragment on Issue {
    id
    title
    titleHTML
    url
    number
    repository {
      nameWithOwner
    }
    state
    stateReason(enableDuplicate: true)
    ...SubIssuesSummary
  }
`

type ParentIssueProps = {
  onLinkClick?: (event: MouseEvent) => void
}

type ParentIssueInternalProps = Omit<ParentIssueProps, 'queryRef'> & {
  issueKey: ParentIssueFragment$key
}

export function ParentIssue({issueKey, onLinkClick}: ParentIssueInternalProps) {
  const data = useFragment(ParentIssueFragment, issueKey)

  useParentIssueSubscription(data.id)
  const {sourceIcon} = useIssueState({
    state: data.state,
    stateReason: data.stateReason,
  })

  const IconComponent = sourceIcon('Issue')
  const title = (data.titleHTML || data.title) as SafeHTMLString

  return (
    <ActionList.LinkItem
      href={data.url}
      target="_blank"
      onClick={
        onLinkClick
          ? (event: React.MouseEvent<HTMLElement>) => {
              onLinkClick(event.nativeEvent)
            }
          : undefined
      }
    >
      <ActionList.LeadingVisual>
        <IconComponent />
      </ActionList.LeadingVisual>
      <ActionList.TrailingVisual>
        <SubIssuesSummary issue={data} />
      </ActionList.TrailingVisual>
      <SafeHTMLText html={title} className="markdown-title" />
      <ActionList.Description variant="block">
        {data.repository.nameWithOwner}#{data.number}
      </ActionList.Description>
    </ActionList.LinkItem>
  )
}
