import type {ReactNode} from 'react'
import {waitFor, renderHook} from '@testing-library/react'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'

import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {mockMarkersData, generateMockThreadMutation} from '../../test-utils/files-changed/markers-mock-data'
import {mockDiffSummariesData} from '../../test-utils/files-changed/diff-summaries-mock-data'
import {useCreateReplyCommentMutation} from '../use-create-reply-comment-mutation'
import type {PullRequestFileTreeDiff} from '../../page-data/payloads/file-tree'
import {diffSummariesKey} from '../../page-data/loaders/use-diff-summaries-data'
import {pendingReviewQueryKey, type PendingReviewIDs} from '../../page-data/payloads/pending-review'
import {threadPreviewsQueryKey} from '../../page-data/payloads/thread-previews'

const pullRequestPathName = '/github/github/pull/1'
const queryClient = getQueryClient()

const inputData = {
  text: 'a reply comment',
  submitBatch: true,
  inReplyTo: 15,
  path: 'owned_files/octocat6/README.md-renamed',
}

beforeEach(() => {
  jest.clearAllMocks()
})

const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={pullRequestPathName}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint and updates the expected query stores', async () => {
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
    generateMockThreadMutation({commentId: 16, commentBody: 'a reply comment'}),
  )

  // Spy on queryClient.invalidateQueries to verify it's called with the right key
  const invalidateQueriesSpy = jest.spyOn(queryClient, 'invalidateQueries')

  const {result} = renderHook(() => useCreateReplyCommentMutation(pullRequestPathName), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate(inputData)
  await waitFor(() => expect(result.current.isSuccess).toEqual(true))
  expect(networkMock).toHaveBeenCalledTimes(1)

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)

  const thread = markersData?.threads[19]
  const newComment = thread?.commentsData.comments.find(c => c.databaseId === 16)

  expect(newComment?.body).toEqual('a reply comment')
  expect(invalidateQueriesSpy).toHaveBeenCalledWith({
    queryKey: threadPreviewsQueryKey(pullRequestPathName),
  })
  expect(markersData?.annotations).toEqual(mockMarkersData.annotations)

  const pendingReviewData = queryClient.getQueryData<PendingReviewIDs>(pendingReviewQueryKey(pullRequestPathName))
  expect(pendingReviewData?.pendingReviewIDs).toEqual([])
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

  const {result} = renderHook(() => useCreateReplyCommentMutation(pullRequestPathName), {
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
