import {mockUUID} from '@github-ui/conversations/test-utils'
import type {SharedThreadPreview, ThreadPreview} from '../../page-data/payloads/thread-previews'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {PendingCommentPreview} from '../../page-data/payloads/pending-review'
import type {PullRequestFilesToolbarProps} from '../../components/toolbar/PullRequestFilesToolbar'
import type {CommitsDropdownProps} from '../../components/diff-filtering/CommitsDropdown'
import {getFilesRoutePullRequest, getFilesRouteRepository} from './pull-request-mock-data'

export const mockPageLimits = {
  annotationsLimit: 50,
  annotationsLimitExceeded: false,
  filesLimit: 300,
  filesLimitExceeded: true,
  reviewThreadsLimit: 40,
  reviewThreadsLimitExceeded: false,
}

export function getPullRequestFilesToolbarMockData(): Omit<PullRequestFilesToolbarProps, 'fileFilter'> {
  return {
    commentBoxConfig: {
      emojiSkinTonePreference: 0,
      pasteUrlsAsPlainText: false,
      useMonospaceFont: false,
    },
    commentBoxSubject: undefined,
    commits: [],
    currentUserLogin: 'test-user',
    diffEntries: [],
    pageLimits: mockPageLimits,
    pullRequest: getFilesRoutePullRequest(),
    repository: getFilesRouteRepository(),
    shouldShowViewedFilesCount: true,
    threadPreviews: [],
    totalFilesCount: 2,
    treeToggleElement: undefined,
    viewedFilesCount: 1,
  }
}

type SharedThreadPreviewData = {[K in keyof SharedThreadPreview]?: SharedThreadPreview[K]}

function buildPreviewBase(thread: SharedThreadPreviewData = {}): SharedThreadPreview {
  return {
    threadId: thread.threadId ?? mockUUID(),
    commentId: thread.commentId ?? '0',
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

const commit1Oid = 'a631866b0075443de782a08024a2368296b83b9e'
const commit2Oid = 'e3884b7d64007768b0240b22dceaa8fc3537731c'
const commit3Oid = 'a9abc6e361fb2bece63858eff142ea361637aa5a'

export function getMockCommitsDropDownPageData(): Omit<CommitsDropdownProps, 'onRangeUpdated'> {
  return {
    commits: [
      {
        actorLogin: 'monalisa',
        createdAt: new Date().toString(),
        messageHeadline: 'commit 1',
        oid: commit1Oid,
        shortOid: commit1Oid.slice(0, 7),
      },
      {
        actorLogin: 'monalisa',
        createdAt: new Date().toString(),
        messageHeadline: 'commit 2',
        oid: commit2Oid,
        shortOid: commit2Oid.slice(0, 7),
      },
      {
        actorLogin: 'monalisa',
        createdAt: new Date().toString(),
        messageHeadline: 'commit 3',
        oid: commit3Oid,
        shortOid: commit3Oid.slice(0, 7),
      },
    ],
  }
}
