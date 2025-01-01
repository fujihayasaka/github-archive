import type {BranchData, BranchPickerData, PullRequestData, PullRequestPickerData} from '../types'

import type {CodeScanningDevelopmentSectionProps} from '../CodeScanningDevelopmentSection'

export const buildLinkedBranch = (data: BranchData) => data

export const buildLinkedPullRequest = (data: PullRequestData) => data

export const buildFoundBranch = (data: BranchPickerData) => data

export const buildFoundPullRequest = (data: PullRequestPickerData) => data

export const foundBranch = buildFoundBranch({
  type: 'branch',
  name: 'Some Branch Name',
})

export const linkedBranch = buildLinkedBranch({
  type: 'branch',
  name: 'fix-alert-1',
  url: '/monalisa/repo',
  lastModifiedAt: '2023-01-25T04:03:48.000-08:00',
})

export const foundPullRequest = buildFoundPullRequest({
  type: 'pull_request',
  title: 'Some PR Title',
  number: 123,
  draft: false,
  merged: false,
  state: 'OPEN',
})

export const linkedPullRequest = buildLinkedPullRequest({
  type: 'pull_request',
  baseRefName: 'main',
  baseRefUrl: '/monalisa/repo',
  createdAt: '2025-03-12T10:04:44.000+01:00',
  isDraft: false,
  number: 1,
  state: 'OPEN',
  title: 'Fix alert 1',
  url: 'http://github.localhost:80/monalisa/repo/pull/1',
  closedAt: null,
  mergedAt: null,
})

export const queryToFind = {
  pull_request: 'title',
  branch: 'name',
  error: 'boom!',
}

export function getCodeScanningDevelopmentSectionProps(
  props?: Partial<CodeScanningDevelopmentSectionProps & {withAlertLinks: boolean}>,
): CodeScanningDevelopmentSectionProps {
  const linkedBranches: BranchData[] = props?.withAlertLinks ? [linkedBranch] : []
  const linkedPullRequests: PullRequestData[] = props?.withAlertLinks ? [linkedPullRequest] : []

  const defaultProps = {
    alertNumber: 1,
    createBranchPath: '/create-path',
    alertTitle: '',
    hasSuggestedFix: false,
    isAlertClosed: false,
    linkedBranches,
    linkedPullRequests,
    pushableByUser: false,
    repository: {
      id: 1,
      name: 'repo',
      ownerLogin: 'monalisa',
      path: '/monalisa/repo',
    },
    updateAlertLinksPath: '/update-alert-links-path',
    linkableItemsSearchPath: '/linkable-items-search-path',
  }

  return {
    ...defaultProps,
    ...(props ? props : {}),
  }
}
