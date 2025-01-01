import {ActionList} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import type {DependencyIssueFragment$key} from './__generated__/DependencyIssueFragment.graphql'
import type React from 'react'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import {useIssueState} from '@github-ui/use-issue-state'

const DependencyIssueFragment = graphql`
  fragment DependencyIssueFragment on Issue {
    title
    titleHTML
    url
    number
    repository {
      nameWithOwner
    }
    state
    stateReason(enableDuplicate: true)
  }
`

type DependencyIssueProps = {
  onLinkClick?: (event: MouseEvent) => void
}

type DependencyIssueInternalProps = Omit<DependencyIssueProps, 'queryRef'> & {
  issueKey: DependencyIssueFragment$key
}

export function DependencyIssue({issueKey, onLinkClick}: DependencyIssueInternalProps) {
  const data = useFragment(DependencyIssueFragment, issueKey)

  // TODO: Add subscription for dependency issues
  // useDependencyIssueSubscription(data.id)
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
      <SafeHTMLText html={title} className="markdown-title" />
      <ActionList.Description variant="block">
        {data.repository.nameWithOwner}#{data.number}
      </ActionList.Description>
    </ActionList.LinkItem>
  )
}
