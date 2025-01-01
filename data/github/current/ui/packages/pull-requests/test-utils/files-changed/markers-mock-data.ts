import type {Comment, Thread} from '@github-ui/conversations'
import type {UseQueryResult} from '@github-ui/react-query'
import {
  useCommentCountFromMarkersData,
  useMarkersData,
  useMarkersDataWithSelectThreadAndAnnotationIDs,
  type Markers,
} from '../../page-data/loaders/use-markers-data'
import {buildAnnotation} from '@github-ui/conversations/test-utils'

/**
 * Generates a mock Comment object for testing purposes
 *
 * @returns {Comment} A mock Comment object with the specified properties
 */
export function generateMockComment({
  authorLogin = 'mockuser',
  id = 'PRRC_kwAQDw',
  databaseId = 15,
  isHidden = false,
  body = 'This is a mock comment body.',
  state = 'ACTIVE',
  viewerCanBlockFromOrg = false,
  viewerCanUnblockFromOrg = false,
}: {
  authorLogin?: string
  id?: string
  databaseId?: number
  isHidden?: boolean
  body?: string
  state?: string
  viewerCanBlockFromOrg?: boolean
  viewerCanUnblockFromOrg?: boolean
}): Comment {
  const mockComment: Omit<Comment, ' $fragmentSpreads'> = {
    author: {
      avatarUrl: 'https://avatars.githubusercontent.com/u/123456?v=4',
      id: 'MDQ6VXNlcjEyMzQ1Ng==',
      login: authorLogin,
      url: 'https://github.com/mockuser',
    },
    authorAssociation: 'COLLABORATOR',
    body,
    // eslint-disable-next-line github/unescaped-html-literal
    bodyHTML: '<p>This is a mock comment body.</p>',
    bodyVersion: '1235',
    createdAt: '2025-03-26T12:00:00Z',
    publishedAt: '2025-03-26T12:05:00Z',
    currentDiffResourcePath: '/path/to/diff',
    id,
    isHidden,
    databaseId,
    lastUserContentEdit: {
      editor: {
        avatarUrl: 'https://avatars.githubusercontent.com/u/654321?v=4',
        id: 'MDQ6VXNlcjY1NDMyMQ==',
        login: 'editoruser',
        url: 'https://github.com/editoruser',
      },
      id: 'edit-456',
    },
    minimizedReason: null,
    outdated: false,
    reference: {
      number: 42,
      text: 'Commit message',
      author: {
        login: 'commitAuthor',
      },
    },
    repository: {
      id: 'repo-789',
      isPrivate: false,
      name: 'mock-repo',
      owner: {
        id: 'owner-101',
        login: 'mockowner',
        url: 'https://github.com/mockowner',
      },
    },
    state,
    viewerCanBlockFromOrg,
    viewerCanMinimize: true,
    viewerCanSeeMinimizeButton: true,
    viewerCanSeeUnminimizeButton: false,
    viewerCanReport: true,
    viewerCanReportToMaintainer: false,
    viewerCanUnblockFromOrg,
    viewerDidAuthor: false,
    viewerRelationship: 'NONE',
    subjectType: 'LINE',
    stafftoolsUrl: null,
    url: 'https://github.com/mock-repo/pull/42#discussion_r123456',
    viewerCanDelete: true,
    viewerCanUpdate: true,
  }

  // Explicitly cast there after checking the above mock comment has everything we need except the fragment spread (used for Relay)
  return mockComment as Comment
}

/**
 * Generates a mock Thread object with customizable properties
 * @param options Configuration options for the thread
 * @returns A mock Thread object
 */
export function generateMockThread({
  id = '15',
  isOutdated = false,
  isResolved = false,
  viewerCanReply = true,
  subjectType = 'LINE',
  comments = [generateMockComment({})],
}: {
  id?: string
  isOutdated?: boolean
  isResolved?: boolean
  viewerCanReply?: boolean
  subjectType?: 'LINE' | 'FILE' | undefined
  comments?: Comment[]
} = {}): Thread {
  return {
    id,
    commentsData: {
      comments,
    },
    isOutdated,
    isResolved,
    viewerCanReply,
    subjectType,
  }
}

export const mockMarkersDataWithPendingComment: Markers = {
  threads: {
    1: {
      commentsData: {
        comments: [
          generateMockComment({
            state: 'pending',
          }),
        ],
      },
      id: '1',
      isOutdated: false,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    },
  },
  annotations: {
    25: buildAnnotation({databaseId: 25}),
  },
}

export const mockMarkersDataWithHiddenComment: Markers = {
  threads: {
    15: generateMockThread({
      comments: [generateMockComment({isHidden: true})],
      id: '15',
      isOutdated: false,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    }),
  },
  annotations: {
    25: buildAnnotation({databaseId: 25}),
  },
}

export function mockUseMarkersData<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useMarkersData as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: {},
    ...result,
  })
}

export function mockUseMarkersDataWithSelectThreadAndAnnotationIDs<TResult>(
  result: Partial<UseQueryResult<TResult>>,
): void {
  ;(useMarkersDataWithSelectThreadAndAnnotationIDs as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: {},
    ...result,
  })
}

export function mockUseCommentCountFromMarkersData<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useCommentCountFromMarkersData as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: {},
    ...result,
  })
}

export const mockMarkersData: Markers = {
  threads: {
    15: generateMockThread({
      comments: [generateMockComment({})],
      id: '15',
      isOutdated: false,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    }),
    1: {
      commentsData: {
        comments: [generateMockComment({})],
      },
      id: '1',
      isOutdated: false,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    },
  },
  annotations: {
    25: buildAnnotation({databaseId: 25}),
  },
}

type MutationResponse = {
  thread: Thread
  comment: Comment
}
export function generateMockThreadMutation({
  id = '19',
  commentId,
  commentBody,
}: {
  id?: string
  commentId: number
  commentBody: string
}): MutationResponse {
  return {
    thread: {
      commentsData: {
        comments: [generateMockComment({}), generateMockComment({databaseId: commentId, body: commentBody})],
      },
      id,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    },
    comment: generateMockComment({databaseId: commentId, body: commentBody}),
  }
}
