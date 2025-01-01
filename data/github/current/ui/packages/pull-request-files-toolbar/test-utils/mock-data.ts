import {buildAnnotation, mockUUID} from '@github-ui/conversations/test-utils'
import type {ToolbarPayload, PullRequest} from '../page-data/payloads/toolbar'
import type {ThreadPreview} from '../page-data/payloads/thread-previews'

export function getPullRequestFilesToolbarMockData(): ToolbarPayload {
  return {
    annotations: [buildAnnotation({})],
    hostUrl: 'https://github.com',
    copilotAccessAllowed: true,
    pullRequest: buildPullRequest(),
    repositoryId: '456',
    threadPreviews: [],
    totalFilesCount: 2,
    viewedFilesCount: 1,
    viewSettings: {
      hideWhitespace: false,
      splitPreference: 'split',
      lineSpacing: 'compact',
    },
  }
}

type ThreadPreviewData = {[K in keyof ThreadPreview]?: ThreadPreview[K]}

export function buildThreadPreview(thread: ThreadPreviewData = {}): ThreadPreview {
  return {
    id: thread.id ?? mockUUID(),
    threadPreviewComments: thread.threadPreviewComments ?? [],
    firstComment: thread.firstComment,
    isResolved: thread.isResolved ?? true,
    isOutdated: thread.isOutdated ?? false,
    line: thread.line ?? 1,
    path: thread.path ?? 'README.md',
  }
}

type PullRequestData = {[K in keyof PullRequest]?: PullRequest[K]}

export function buildPullRequest(data: PullRequestData = {}): PullRequest {
  return {
    author: data.author ?? {login: 'test-user'},
    comparison: data.comparison ?? {
      newCommit: {
        oid: 'mock-head-oid',
      },
    },
    headRefOid: data.headRefOid ?? 'mock-head-oid',
    id: data.id ?? 'fakeId',
    pathName: data.pathName ?? '/test-user/test-repo/pull/1',
    repository: data.repository ?? {
      viewerPermission: 'WRITE',
    },
    state: data.state ?? 'OPEN',
    viewerCanLeaveNonCommentReviews: data.viewerCanLeaveNonCommentReviews ?? true,
    viewerHasViolatedPushPolicy: data.viewerHasViolatedPushPolicy ?? false,
  }
}
