import type {ReactNode} from 'react'
import {waitFor, renderHook} from '@testing-library/react'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'

import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {mockMarkersData, generateMockThreadMutation} from '../../test-utils/files-changed/markers-mock-data'
import {useCreateReviewCommentMutation, type Side} from '../use-create-review-comment-mutation'
import type {PullRequestFileTreeDiff} from '../../page-data/payloads/file-tree'
import {mockDiffSummariesData} from '../../test-utils/files-changed/diff-summaries-mock-data'
import {diffSummariesKey} from '../../page-data/loaders/use-diff-summaries-data'
import {pendingReviewQueryKey, type PendingReviewIDs} from '../../page-data/payloads/pending-review'

const pullRequestPathName = '/github/github/pull/1'
const queryClient = getQueryClient()

const inputData = {
  text: 'a new comment',
  line: 3,
  path: 'new-file',
  side: 'right' as Side,
  startSide: undefined,
  submitBatch: true,
}

beforeEach(() => {
  jest.clearAllMocks()
})

const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={pullRequestPathName}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint and updates expected query stores', async () => {
  const markersQueryKey = pullRequestMarkersKey(pullRequestPathName)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)
  queryClient.setQueryData<PullRequestFileTreeDiff[]>(diffSummariesKey(pullRequestPathName), mockDiffSummariesData)
  queryClient.setQueryData<PendingReviewIDs>(pendingReviewQueryKey(pullRequestPathName), {
    id: undefined,
    pendingReviewIDs: [],
    comments: [],
  })
  const networkMock = mockFetch.mockRouteOnce(
    /create_review_comment/,
    generateMockThreadMutation({id: '20', commentId: 16, commentBody: 'a new comment'}),
  )

  const {result} = renderHook(() => useCreateReviewCommentMutation(pullRequestPathName), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate(inputData)
  await waitFor(() => expect(result.current.isSuccess).toEqual(true))
  expect(networkMock).toHaveBeenCalledTimes(1)

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)
  const summaries = queryClient.getQueryData<PullRequestFileTreeDiff[]>(diffSummariesKey(pullRequestPathName))

  const thread = markersData?.threads[20]
  const newComment = thread?.commentsData.comments.find(c => c.databaseId === 16)
  const tocDiff = summaries?.find((d: PullRequestFileTreeDiff) => d.path === inputData.path)

  expect(newComment?.body).toEqual('a new comment')
  expect(tocDiff?.markersMap).toHaveProperty('R3')

  const lineMarkers = tocDiff?.markersMap?.['R3']
  expect(lineMarkers).toBeDefined()
  expect(lineMarkers).toHaveProperty('threads')
  expect(lineMarkers).toHaveProperty('annotations')

  expect(lineMarkers?.threads).toContainEqual(
    expect.objectContaining({
      id: 20,
    }),
  )

  expect(Array.isArray(lineMarkers?.annotations)).toBe(true)
  expect(markersData?.annotations).toEqual(mockMarkersData.annotations)

  const pendingReviewData = queryClient.getQueryData<PendingReviewIDs>(pendingReviewQueryKey(pullRequestPathName))
  expect(pendingReviewData?.pendingReviewIDs).toEqual([])
})

test('it preserves existing annotations when adding a thread', async () => {
  // Create mock data with annotations in the markers map
  const mockDataWithAnnotations = JSON.parse(JSON.stringify(mockDiffSummariesData))
  // Add an annotation to the R3 position
  mockDataWithAnnotations[1].markersMap.R3 = {
    threads: [],
    annotations: [{id: 123}],
  }

  const markersQueryKey = pullRequestMarkersKey(pullRequestPathName)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)
  queryClient.setQueryData<PullRequestFileTreeDiff[]>(diffSummariesKey(pullRequestPathName), mockDataWithAnnotations)

  mockFetch.mockRouteOnce(
    /create_review_comment/,
    generateMockThreadMutation({id: '20', commentId: 16, commentBody: 'a new comment'}),
  )

  const {result} = renderHook(() => useCreateReviewCommentMutation(pullRequestPathName), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate(inputData)
  await waitFor(() => expect(result.current.isSuccess).toEqual(true))

  const summaries = queryClient.getQueryData<PullRequestFileTreeDiff[]>(diffSummariesKey(pullRequestPathName))
  const tocDiff = summaries?.find((d: PullRequestFileTreeDiff) => d.path === inputData.path)
  const lineMarkers = tocDiff?.markersMap?.['R3']

  expect(lineMarkers?.threads).toContainEqual(expect.objectContaining({id: 20}))
  expect(lineMarkers?.annotations).toContainEqual(expect.objectContaining({id: 123}))
})

test('it updates the pending review query store when submitBatch is false', async () => {
  const markersQueryKey = pullRequestMarkersKey(pullRequestPathName)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)
  queryClient.setQueryData<PullRequestFileTreeDiff[]>(diffSummariesKey(pullRequestPathName), mockDiffSummariesData)
  queryClient.setQueryData<PendingReviewIDs>(pendingReviewQueryKey(pullRequestPathName), {
    id: '123',
    pendingReviewIDs: [10],
    comments: [],
  })

  const networkMock = mockFetch.mockRouteOnce(
    /create_review_comment/,
    generateMockThreadMutation({commentId: 16, commentBody: 'a reply comment', id: '19'}),
  )

  const {result} = renderHook(() => useCreateReviewCommentMutation(pullRequestPathName), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate({
    ...inputData,
    submitBatch: false,
  })

  await waitFor(() => expect(result.current.isSuccess).toEqual(true))
  expect(networkMock).toHaveBeenCalledTimes(1)

  const pendingReviewData = queryClient.getQueryData<PendingReviewIDs>(pendingReviewQueryKey(pullRequestPathName))

  expect(pendingReviewData?.pendingReviewIDs).toContain(19)
  expect(pendingReviewData?.pendingReviewIDs).toContain(10)
  expect(pendingReviewData?.pendingReviewIDs.length).toEqual(2)
})
