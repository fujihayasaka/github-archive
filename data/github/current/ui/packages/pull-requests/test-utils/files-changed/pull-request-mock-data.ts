import {type PullRequest, PullRequestState} from '../../page-data/payloads/toolbar'
import {signChannel} from '@github-ui/use-alive/test-utils'
import {getHeaderPageData} from '../header-mock-data'

export function getFilesRoutePullRequest(data: PullRequestData = {}) {
  const filesPullRequest = buildFilesPullRequest(data)
  const headerData = getHeaderPageData()

  return {
    ...headerData.pullRequest,
    ...filesPullRequest,
  }
}

export function getFilesRouteRepository() {
  const filesPullRequest = buildFilesPullRequest()
  const headerData = getHeaderPageData()

  return {
    ...filesPullRequest.repository,
    ...headerData.repository,
  }
}

type PullRequestData = {[K in keyof PullRequest]?: PullRequest[K]}

// TODO - this is a temporary solution until we consoldate types and clean up the mock data
// namely moving the PullRequest type out of the toolbar payload file
function buildFilesPullRequest(data: PullRequestData = {}): PullRequest {
  return {
    aliveChannel: signChannel(data.aliveChannel ?? 'prs-alive-channel'),
    author: data.author ?? {login: 'test-user'},
    comparison: data.comparison ?? {
      baseOid: 'mock-base-oid',
      headOid: 'mock-head-oid',
    },
    id: data.id ?? 'fakeId',
    pathName: data.pathName ?? '/test-user/test-repo/pull/1',
    repository: data.repository ?? {
      id: 456,
      viewerPermission: 'WRITE',
    },
    state: data.state ?? PullRequestState.Open,
    viewerAllowedNonCommentReviewTypes: data.viewerAllowedNonCommentReviewTypes ?? ['APPROVE', 'REQUEST_CHANGES'],
    viewerIsCopilotAttributed: data.viewerIsCopilotAttributed ?? false,
    viewerHasViolatedPushPolicy: data.viewerHasViolatedPushPolicy ?? false,
  }
}
