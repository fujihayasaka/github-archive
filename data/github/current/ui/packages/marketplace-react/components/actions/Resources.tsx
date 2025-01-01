import {Stack, CounterLabel} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {
  CommentDiscussionIcon,
  IssueOpenedIcon,
  ReportIcon,
  RepoIcon,
  LawIcon,
  GitPullRequestIcon,
  EyeClosedIcon,
} from '@primer/octicons-react'
import {discussionsPath, repoIssuesPath, repoPullRequestsPath, reportAbusePath, repositoryPath} from '@github-ui/paths'
import {useState, useMemo} from 'react'
import type {Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'
import {DelistForm} from './DelistForm'
import {ResourceList} from '../sidebar-shared/ResourceList'

interface ResourcesProps {
  action: ActionListing
  repository: Repository
  repoAdminableByViewer: boolean
}

export function Resources(props: ResourcesProps) {
  const {repository, action, repoAdminableByViewer} = props
  const {name, owner, hasSecurityPolicy, isDiscussionsActive, hasIssues, openIssuesCount, openPullRequestsCount} =
    repository

  const [isDelistDialogOpen, setIsDelistDialogOpen] = useState(false)
  const openDelistDialog = () => {
    setIsDelistDialogOpen(true)
  }
  const closeDelistDialog = () => {
    setIsDelistDialogOpen(false)
  }

  const linkItems = useMemo(
    () => [
      {
        url: isDiscussionsActive && owner && name ? discussionsPath({owner, repo: name}) : undefined,
        component: CommentDiscussionIcon,
        text: 'Start a discussion',
      },
      {
        url: hasIssues && owner && name ? repoIssuesPath(owner, name) : undefined,
        component: IssueOpenedIcon,
        text: 'Open an issue',
        trailingVisual: <CounterLabel>{openIssuesCount}</CounterLabel>,
      },
      {
        url: owner && name ? repoPullRequestsPath(owner, name) : undefined,
        component: GitPullRequestIcon,
        text: 'Pull requests',
        trailingVisual: <CounterLabel>{openPullRequestsCount}</CounterLabel>,
      },
      {
        url: owner && name ? repositoryPath({owner, repo: name}) : undefined,
        component: RepoIcon,
        text: 'View source code',
      },
      {
        url: hasSecurityPolicy && owner && name ? `${repositoryPath({owner, repo: name})}#security-ov-file` : undefined,
        component: LawIcon,
        text: 'Security policy',
      },
      {
        url: reportAbusePath({report: `${action.name} (GitHub Action)`}),
        component: ReportIcon,
        text: 'Report abuse',
      },
    ],
    [
      action.name,
      hasIssues,
      hasSecurityPolicy,
      isDiscussionsActive,
      name,
      openIssuesCount,
      openPullRequestsCount,
      owner,
    ],
  )
  const dangerItems = useMemo(
    () => [
      {
        onSelect: repoAdminableByViewer && action.slug ? () => openDelistDialog() : undefined,
        component: EyeClosedIcon,
        text: 'Delist action',
      },
    ],
    [action.slug, repoAdminableByViewer],
  )

  return (
    <Stack gap={'condensed'} data-testid={'resources'}>
      <SidebarHeading title="Resources" htmlTag={'h2'} />
      <ResourceList linkItems={linkItems} dangerItems={dangerItems} />
      <DelistForm
        action={action}
        repoAdminableByViewer={repoAdminableByViewer}
        isDialogOpen={isDelistDialogOpen}
        onDialogClose={closeDelistDialog}
      />
    </Stack>
  )
}
