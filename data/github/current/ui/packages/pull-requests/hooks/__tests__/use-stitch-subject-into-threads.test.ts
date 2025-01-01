import {renderHook} from '@testing-library/react'
import {useStitchSubjectIntoThreads} from '../use-stitch-subject-into-threads'
import type {ThreadPreview} from '../../page-data/payloads/thread-previews'
import type {Thread, ThreadSubject} from '@github-ui/conversations'

describe('useStitchSubjectIntoThreads', () => {
  it('should not modify initialMarkers if it is undefined', () => {
    const initialMarkers = undefined
    const threadPreviews = [
      {
        threadId: '2',
        commentId: '2',
        isOutdated: false,
        isResolved: true,
        line: 42,
        path: 'src/components/Button.tsx',
        subject: 'test' as unknown as ThreadSubject,
        subjectType: 'LINE',
        threadPreviewComments: [
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
              login: 'octocat',
            },
          },
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
              login: 'hubot',
            },
          },
        ],
      },
      {
        threadId: '1',
        commentId: '1',
        isOutdated: false,
        isResolved: true,
        line: 42,
        path: 'src/components/Button.tsx',
        subject: 'test2' as unknown as ThreadSubject,
        subjectType: 'LINE',
        threadPreviewComments: [
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
              login: 'octocat',
            },
          },
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
              login: 'hubot',
            },
          },
        ],
      },
    ] as ThreadPreview[]

    const {result} = renderHook(() => useStitchSubjectIntoThreads(initialMarkers, threadPreviews))

    expect(result.current).toBeUndefined()
  })

  it('should correctly stitch subjects into threads when thread IDs match', () => {
    const initialMarkers = {
      threads: {
        1: {
          commentsData: {comments: []},
          id: 1 as unknown as string,
          viewerCanReply: true,
          subjectType: 'LINE' as 'LINE' | 'FILE' | undefined,
        } as Thread,
        2: {
          commentsData: {comments: []},
          id: 2 as unknown as string,
          viewerCanReply: true,
          subjectType: 'LINE' as 'LINE' | 'FILE' | undefined,
        } as Thread,
      },
      annotations: {},
    }
    const threadPreviews = [
      {
        threadId: '2',
        commentId: '2',
        isOutdated: false,
        isResolved: true,
        line: 42,
        path: 'src/components/Button.tsx',
        subject: 'test' as unknown as ThreadSubject,
        subjectType: 'LINE',
        threadPreviewComments: [
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
              login: 'octocat',
            },
          },
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
              login: 'hubot',
            },
          },
        ],
      },
      {
        threadId: '1',
        commentId: '1',
        isOutdated: false,
        isResolved: true,
        line: 42,
        path: 'src/components/Button.tsx',
        subject: 'test2' as unknown as ThreadSubject,
        subjectType: 'LINE',
        threadPreviewComments: [
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
              login: 'octocat',
            },
          },
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
              login: 'hubot',
            },
          },
        ],
      },
    ] as ThreadPreview[]

    renderHook(() => useStitchSubjectIntoThreads(initialMarkers, threadPreviews))

    expect(initialMarkers.threads[1].subject).toBe('test2')
    expect(initialMarkers.threads[2].subject).toBe('test')
  })

  it('should not modify threads if no matching threadPreviews are found', () => {
    const initialMarkers = {
      threads: {
        1: {
          commentsData: {comments: []},
          id: 1 as unknown as string,
          viewerCanReply: true,
          subjectType: 'LINE' as 'LINE' | 'FILE' | undefined,
        } as Thread,
        2: {
          commentsData: {comments: []},
          id: 2 as unknown as string,
          viewerCanReply: true,
          subjectType: 'LINE' as 'LINE' | 'FILE' | undefined,
        } as Thread,
      },
      annotations: {},
    }
    const threadPreviews = [
      {
        threadId: '6',
        commentId: '6',
        isOutdated: false,
        isResolved: true,
        line: 42,
        path: 'src/components/Button.tsx',
        subject: 'test' as unknown as ThreadSubject,
        subjectType: 'LINE',
        threadPreviewComments: [
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
              login: 'octocat',
            },
          },
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
              login: 'hubot',
            },
          },
        ],
      },
      {
        threadId: '5',
        commentId: '5',
        isOutdated: false,
        isResolved: true,
        line: 42,
        path: 'src/components/Button.tsx',
        subject: 'test2' as unknown as ThreadSubject,
        subjectType: 'LINE',
        threadPreviewComments: [
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
              login: 'octocat',
            },
          },
          {
            author: {
              avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
              login: 'hubot',
            },
          },
        ],
      },
    ] as ThreadPreview[]

    renderHook(() => useStitchSubjectIntoThreads(initialMarkers, threadPreviews))

    expect(initialMarkers.threads[1].subject).toBeUndefined()
    expect(initialMarkers.threads[2].subject).toBeUndefined()
  })

  it('should handle empty threadPreviews gracefully', () => {
    const initialMarkers = {
      threads: {
        1: {
          commentsData: {comments: []},
          id: 1 as unknown as string,
          viewerCanReply: true,
          subjectType: 'LINE' as 'LINE' | 'FILE' | undefined,
        } as Thread,
        2: {
          commentsData: {comments: []},
          id: 2 as unknown as string,
          viewerCanReply: true,
          subjectType: 'LINE' as 'LINE' | 'FILE' | undefined,
        } as Thread,
      },
      annotations: {},
    }
    const threadPreviews: ThreadPreview[] = []

    renderHook(() => useStitchSubjectIntoThreads(initialMarkers, threadPreviews))

    expect(initialMarkers.threads[1].subject).toBeUndefined()
    expect(initialMarkers.threads[2].subject).toBeUndefined()
  })
})
