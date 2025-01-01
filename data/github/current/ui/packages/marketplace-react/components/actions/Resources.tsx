import {Link, Stack} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {
  CommentDiscussionIcon,
  IssueOpenedIcon,
  ReportIcon,
  RepoIcon,
  LawIcon,
  GitPullRequestIcon,
} from '@primer/octicons-react'
import {discussionsPath, repoIssuesPath, repoPullRequestsPath, reportAbusePath, repositoryPath} from '@github-ui/paths'
import type {Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface ResourcesProps {
  action: ActionListing
  repository: Repository
}

export function Resources(props: ResourcesProps) {
  const {repository, action} = props
  const {name, owner, hasSecurityPolicy, mitLicensePath, isDiscussionsActive, hasIssues} = repository

  return (
    <Stack gap={'condensed'} data-testid={'resources'}>
      <SidebarHeading title="Resources" htmlTag={'h2'} />
      {isDiscussionsActive && owner && name && (
        <Link href={discussionsPath({owner, repo: name})} muted className="d-block">
          <CommentDiscussionIcon size={16} className="mr-2" />
          Start a discussion
        </Link>
      )}
      {hasIssues && owner && name && (
        <Link href={repoIssuesPath(owner, name)} muted className="d-block">
          <IssueOpenedIcon size={16} className="mr-2" />
          Open an issue
        </Link>
      )}
      {owner && name && (
        <Link href={repoPullRequestsPath(owner, name)} muted className="d-block">
          <GitPullRequestIcon size={16} className="mr-2" />
          Pull requests
        </Link>
      )}
      {owner && name && (
        <Link href={repositoryPath({owner, repo: name})} muted className="d-block">
          <RepoIcon size={16} className="mr-2" />
          View source code
        </Link>
      )}
      {hasSecurityPolicy && owner && name && (
        <Link href={`${repositoryPath({owner, repo: name})}#security-ov-file`} muted className="d-block">
          <LawIcon size={16} className="mr-2" />
          Security policy
        </Link>
      )}
      {mitLicensePath && (
        <Link href={mitLicensePath} muted className="d-block">
          <LawIcon size={16} className="mr-2" />
          MIT license
        </Link>
      )}
      <Link href={reportAbusePath({report: `${action.name} (GitHub Action)`})} muted className="d-block">
        <ReportIcon size={16} className="mr-2" />
        Report abuse
      </Link>
    </Stack>
  )
}
