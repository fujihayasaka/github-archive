import {buildAnnotation, mockUUID} from '@github-ui/conversations/test-utils'
import {type ToolbarPayload, type PullRequest, PullRequestState} from '../page-data/payloads/toolbar'
import type {SharedThreadPreview, ThreadPreview} from '../page-data/payloads/thread-previews'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {PendingCommentPreview} from '../page-data/payloads/pending-review'
import {signChannel} from '@github-ui/use-alive/test-utils'

export function getPullRequestFilesToolbarMockData(): ToolbarPayload {
  return {
    annotations: [buildAnnotation({})],
    copilotAccessAllowed: true,
    currentUserLogin: 'test-user',
    isFileTreeExpanded: true,
    pullRequest: buildPullRequest(),
    shouldShowViewedFilesCount: true,
    threadPreviews: [],
    totalFilesCount: 2,
    viewedFilesCount: 1,
    viewerPendingReview: {
      id: undefined,
      comments: [],
    },
  }
}

type SharedThreadPreviewData = {[K in keyof SharedThreadPreview]?: SharedThreadPreview[K]}

function buildPreviewBase(thread: SharedThreadPreviewData = {}): SharedThreadPreview {
  return {
    id: thread.id ?? mockUUID(),
    threadPreviewComments: thread.threadPreviewComments ?? [],
    isResolved: thread.isResolved ?? true,
    isOutdated: thread.isOutdated ?? false,
    line: thread.line ?? 1,
    path: thread.path ?? 'README.md',
  }
}

type ThreadPreviewData = {[K in keyof ThreadPreview]?: ThreadPreview[K]}

export function buildThreadPreview(thread: ThreadPreviewData = {}): ThreadPreview {
  return {
    ...buildPreviewBase(thread),
    firstComment: thread.firstComment,
  }
}

type PendingCommentPreviewData = {[K in keyof PendingCommentPreview]?: PendingCommentPreview[K]}

export function buildPendingCommentPreview(thread: PendingCommentPreviewData = {}): PendingCommentPreview {
  return {
    ...buildPreviewBase(thread),
    bodyHTML: thread.bodyHTML ?? ('' as SafeHTMLString),
  }
}

type PullRequestData = {[K in keyof PullRequest]?: PullRequest[K]}

export function buildPullRequest(data: PullRequestData = {}): PullRequest {
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
    viewerCanLeaveNonCommentReviews: data.viewerCanLeaveNonCommentReviews ?? true,
    viewerHasViolatedPushPolicy: data.viewerHasViolatedPushPolicy ?? false,
  }
}
