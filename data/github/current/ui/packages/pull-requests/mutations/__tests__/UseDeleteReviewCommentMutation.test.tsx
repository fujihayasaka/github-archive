import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import type {ReactNode} from 'react'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {generateMockComment, mockMarkersData} from '../../test-utils/files-changed/markers-mock-data'
import {renderHook, waitFor} from '@testing-library/react'
import {useDeleteReviewCommentMutation} from '../use-delete-review-comment-mutation'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {mockDiffSummariesData} from '../../test-utils/files-changed/diff-summaries-mock-data'
import type {PullRequestFileTreeDiff} from '../../page-data/payloads/file-tree'
import {diffSummariesKey} from '../../page-data/loaders/use-diff-summaries-data'

const basePath = '/github/github/pull/3'
const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={basePath}>{children}</PageDataContextProvider>
)

describe('last comment in the thread', () => {
  test('deletes thread and updates comment count', async () => {
    const queryClient = getQueryClient()
    const markersQueryKey = pullRequestMarkersKey(basePath)
    queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)
    const summaryQueryKey = diffSummariesKey(basePath)
    queryClient.setQueryData(summaryQueryKey, mockDiffSummariesData)

    const mockedResponse = {ok: true}
    mockFetch.mockRouteOnce(/review_comments\/15/, mockedResponse, {status: 204})

    let summaryData = queryClient.getQueryData<PullRequestFileTreeDiff[]>(summaryQueryKey)
    expect(summaryData?.[1]?.markersMap?.['R4']).toBeDefined()
    expect(summaryData?.[1]?.markersMap?.['R4']?.annotations.length).toEqual(0)

    const {result} = renderHook(() => useDeleteReviewCommentMutation(basePath), {
      wrapper: withBaseProvidersWrapper(wrapper),
    })
    result.current.mutate({
      commentId: 'PRRC_kwAQDw',
      threadId: '15',
      filePath: 'new-file',
    })

    await waitFor(() => {
      expect(result.current.isSuccess).toEqual(true)
    })

    const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!
    expect(markersData.threads[15]).toBeUndefined()

    summaryData = queryClient.getQueryData<PullRequestFileTreeDiff[]>(summaryQueryKey)!
    expect(summaryData[1]?.markersMap?.['R4']).toBeUndefined()
  })

  test('preserves marker when thread is deleted but annotations exist', async () => {
    const markersQueryKey = pullRequestMarkersKey(basePath)
    const queryClient = getQueryClient()
    queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)
    const summaryQueryKey = [PageData.diffSummaries, basePath]
    queryClient.setQueryData(summaryQueryKey, mockDiffSummariesData)

    const mockedResponse = {ok: true}
    mockFetch.mockRouteOnce(/review_comments\/1/, mockedResponse, {status: 204})

    let summaryData = queryClient.getQueryData<PullRequestFileTreeDiff[]>(summaryQueryKey)
    const summaryForFile = summaryData?.[6]
    expect(summaryForFile?.markersMap?.['R25']).toBeDefined()
    expect(summaryForFile?.markersMap?.['R25']?.threads.length).toEqual(1)
    expect(summaryForFile?.markersMap?.['R25']?.annotations.length).toEqual(1)

    let markersData = queryClient.getQueryData<Markers>(markersQueryKey)!
    expect(markersData.threads[1]).toBeDefined()

    const {result} = renderHook(() => useDeleteReviewCommentMutation(basePath), {
      wrapper: withBaseProvidersWrapper(wrapper),
    })
    result.current.mutate({
      commentId: 'PRRC_kwAQDw',
      threadId: '1',
      filePath: 'app/components/pull_requests/file_tree/root_component.rb',
    })

    await waitFor(() => {
      expect(result.current.isSuccess).toEqual(true)
    })

    markersData = queryClient.getQueryData<Markers>(markersQueryKey)!
    expect(markersData.threads[1]).toBeUndefined()

    summaryData = queryClient.getQueryData<PullRequestFileTreeDiff[]>(summaryQueryKey)!
    expect(summaryData[6]?.markersMap?.['R25']?.threads.length).toEqual(0)
    expect(summaryData[6]?.markersMap?.['R25']?.annotations.length).toEqual(1)
  })
})

describe('not the last comment in the thread', () => {
  test('deletes comment and does not update comment count', async () => {
    const mockedMarkersData: Markers = {
      threads: {
        16: {
          commentsData: {
            comments: [
              generateMockComment({id: 'PR_gwA1', databaseId: 16}),
              generateMockComment({id: 'PR_gwA2', databaseId: 17}),
            ],
          },
          id: '16',
          isOutdated: false,
          isResolved: false,
          viewerCanReply: false,
          subjectType: 'LINE',
        },
      },
      annotations: {},
    }

    const queryClient = getQueryClient()
    const markersQueryKey = pullRequestMarkersKey(basePath)
    queryClient.setQueryData<Markers>(markersQueryKey, mockedMarkersData)
    const summaryQueryKey = [PageData.diffSummaries, basePath]
    queryClient.setQueryData(summaryQueryKey, mockDiffSummariesData)
    const mockedResponse = {ok: true}
    mockFetch.mockRouteOnce(/review_comments\/16/, mockedResponse, {status: 204})

    const summaryData = queryClient.getQueryData<PullRequestFileTreeDiff[]>(summaryQueryKey)!
    expect(summaryData[1]?.markersMap?.['R4']).toBeDefined()

    const {result} = renderHook(() => useDeleteReviewCommentMutation(basePath), {
      wrapper: withBaseProvidersWrapper(wrapper),
    })

    const markersData = queryClient.getQueryData<Markers>(markersQueryKey)
    expect(markersData?.threads[16]).toBeDefined()
    const comment = markersData?.threads[16]?.commentsData.comments.find(c => c.databaseId === 15)
    expect(comment).toBeUndefined()

    result.current.mutate({
      commentId: 'PR_gwA1',
      threadId: '16',
      filePath: 'new-file',
    })

    await waitFor(() => {
      expect(result.current.isSuccess).toEqual(true)
    })

    const newSummaryData = queryClient.getQueryData<PullRequestFileTreeDiff[]>(summaryQueryKey)
    expect(newSummaryData).toBeDefined()

    const fileTreeDiff = newSummaryData?.[1]
    expect(fileTreeDiff).toBeDefined()
    expect(fileTreeDiff?.markersMap?.['R4']).toBeDefined()
  })
})
