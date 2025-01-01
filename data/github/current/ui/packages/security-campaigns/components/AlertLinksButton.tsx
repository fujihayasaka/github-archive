import {useCallback, useState} from 'react'
import {AnchoredOverlay, Button} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {GitBranchIcon, GitPullRequestIcon} from '@primer/octicons-react'
import {branchPath, issueLinkedPullRequestHovercardPath, pullRequestPath} from '@github-ui/paths'
import type {LinkedBranch} from '../types/linked-branch'
import type {LinkedPullRequest} from '../types/linked-pull-request'
import {AlertLinksOverlayContent} from './AlertLinksOverlayContent'
import {getLinkedPullRequestIcon, getLinkedPullRequestIconColor, LinkedPullRequestIcon} from './LinkedPullRequestIcon'
import type {Repository} from '../types/repository'

import styles from './AlertLinksButton.module.css'

export type AlertLinksButtonProps = {
  linkedPullRequests: LinkedPullRequest[]
  linkedBranches: LinkedBranch[]
  repository: Repository
}

export function AlertLinksButton({linkedPullRequests, linkedBranches, repository}: AlertLinksButtonProps) {
  const [open, setOpen] = useState(false)

  // The leadingVisual prop requires a component to be passed in, not a rendered component.
  // Since we have different components that can be rendered depending on how many linked pull requests/branches
  // there are, we need to wrap them in a function so that we can pass that function to the leadingVisual prop.
  const leadingVisual = useCallback(() => {
    // If there are no linked branches, we should check whether all PRs are in the same state. If so, we can render
    // an icon for that state.
    if (linkedBranches.length === 0) {
      const iconColors = new Set(
        linkedPullRequests.map(linkedPullRequest => getLinkedPullRequestIconColor(linkedPullRequest)),
      )
      const icons = new Set(
        linkedPullRequests.map(linkedPullRequest => getLinkedPullRequestIcon(linkedPullRequest).displayName),
      )

      // If the icon color and icon are the same for all linked pull requests, we can just render that
      // icon since all PRs are in the same state.
      if (iconColors.size === 1 && icons.size === 1 && linkedPullRequests[0]) {
        const linkedPullRequest = linkedPullRequests[0]
        return <LinkedPullRequestIcon linkedPullRequest={linkedPullRequest} />
      }
    }

    // If there are no linked PRs, we can render a branch icon since this means we either only have linked branches
    // or no links at all (which will not show a button at all).
    if (linkedPullRequests.length === 0) {
      return <Octicon icon={GitBranchIcon} color="fg.muted" />
    }

    // Otherwise, we'll render the default GitPullRequestIcon with the fg.muted color
    return <Octicon icon={GitPullRequestIcon} color="fg.muted" />
  }, [linkedPullRequests, linkedBranches])

  if (linkedPullRequests.length === 0 && linkedBranches.length === 0) {
    return null
  }

  if (linkedPullRequests.length === 1 && linkedBranches.length === 0 && linkedPullRequests[0]) {
    // If there is only 1 linked PR, we can just link to that PR
    return (
      <Button
        as="a"
        href={pullRequestPath({repo: repository, number: linkedPullRequests[0].number})}
        variant="invisible"
        leadingVisual={leadingVisual}
        data-hovercard-url={issueLinkedPullRequestHovercardPath({
          owner: repository.ownerLogin,
          repo: repository.name,
          pullRequestNumber: linkedPullRequests[0].number,
        })}
      >
        {linkedPullRequests.length + linkedBranches.length}
      </Button>
    )
  }

  if (linkedBranches.length === 1 && linkedPullRequests.length === 0 && linkedBranches[0]) {
    // If there is only 1 linked branch, we can just link to that branch
    return (
      <Button
        as="a"
        href={branchPath({owner: repository.ownerLogin, repo: repository.name, branch: linkedBranches[0].name})}
        variant="invisible"
        leadingVisual={leadingVisual}
      >
        {linkedPullRequests.length + linkedBranches.length}
      </Button>
    )
  }

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      renderAnchor={props => (
        <Button variant="invisible" leadingVisual={leadingVisual} {...props}>
          {linkedPullRequests.length + linkedBranches.length}
        </Button>
      )}
    >
      <div className={`width-full height-full ${styles.overlayContainer}`}>
        <AlertLinksOverlayContent
          repository={repository}
          linkedPullRequests={linkedPullRequests}
          linkedBranches={linkedBranches}
        />
      </div>
    </AnchoredOverlay>
  )
}
