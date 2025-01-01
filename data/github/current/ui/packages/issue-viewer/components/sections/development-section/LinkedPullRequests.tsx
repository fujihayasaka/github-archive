import {ActionList} from '@primer/react'
import {PullRequestStateIcons} from '@github-ui/use-issue-state/Icons'
import {getPrState} from '@github-ui/item-picker/PullRequestPicker'
import type {PullRequestPickerPullRequest$data} from '@github-ui/item-picker/PullRequestPickerPullRequest.graphql'

type LinkedPullRequestsProps = {
  linkedPullRequests: PullRequestPickerPullRequest$data[]
}

export function LinkedPullRequests({linkedPullRequests}: LinkedPullRequestsProps) {
  return (
    <>
      {linkedPullRequests.map(pullRequest => {
        return (
          <ActionList.LinkItem
            href={pullRequest.url}
            target="_blank"
            key={pullRequest.id}
            sx={{
              span: {
                fontSize: 0,
                lineHeight: 1.5,
                marginBlockEnd: '0',
              },
            }}
          >
            <ActionList.LeadingVisual>{getPrIcon(pullRequest)}</ActionList.LeadingVisual>
            {pullRequest.title}
            <ActionList.Description variant="block">{pullRequest.repository.nameWithOwner}</ActionList.Description>
          </ActionList.LinkItem>
        )
      })}
    </>
  )
}

function getPrIcon(pullRequest: PullRequestPickerPullRequest$data) {
  const prState = getPrState(
    pullRequest.isDraft && pullRequest.state === 'OPEN',
    pullRequest.isInMergeQueue,
    pullRequest.state,
  )
  const Icon = PullRequestStateIcons[prState]
  return <Icon />
}
