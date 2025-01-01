import {renderHook, waitFor} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {
  type UpdateReviewCommentMutationResponse,
  useUpdateReviewCommentMutation,
} from '../use-update-review-comment-mutation'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import type {ReactNode} from 'react'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {mockMarkersData} from '../../test-utils/files-changed/markers-mock-data'

const basePath = '/github/github/pull/3'
const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={basePath}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint and updates expected query stores', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)

  const newBody = `updated body`
  const updateBodyArgs = {commentId: '1', body: newBody}
  const mockedResponse = {
    ok: true,
    json: async (): Promise<UpdateReviewCommentMutationResponse> => ({
      body: newBody,
      bodyHTML: newBody,
      commentDatabaseId: 15,
      threadId: 15,
    }),
  }

  mockFetch.mockRouteOnce(/update_review_comment(?!.*body_version)/, updateBodyArgs, mockedResponse)

  const {result} = renderHook(() => useUpdateReviewCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate(updateBodyArgs)

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const thread = markersData.threads[15]
  const updatedComment = thread?.commentsData.comments.find(c => c.databaseId === 15)
  expect(updatedComment?.body).toEqual(newBody)
  expect(updatedComment?.bodyHTML).toEqual(newBody)
  expectMockFetchCalledTimes(/update_review_comment/, 1)
  expect(markersData.annotations).toEqual(mockMarkersData.annotations)
})

test('skips updating the thread if the thread does not already exist', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, {threads: {}, annotations: {}})

  const newBody = `updated body`
  const updateBodyArgs = {commentId: '1', body: newBody}
  const mockedResponse = {
    ok: true,
    json: async (): Promise<UpdateReviewCommentMutationResponse> => ({
      body: newBody,
      bodyHTML: newBody,
      commentDatabaseId: 15,
      threadId: 15,
    }),
  }

  mockFetch.mockRouteOnce(/update_review_comment(?!.*body_version)/, updateBodyArgs, mockedResponse)

  const {result} = renderHook(() => useUpdateReviewCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate(updateBodyArgs)

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)
  expect(markersData).toBeDefined()
  const thread = markersData?.threads[15]
  expect(thread).toBeUndefined()
  expectMockFetchCalledTimes(/update_review_comment/, 1)
})

test('appends the body version to params if it is provided', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, {threads: {}, annotations: {}})

  const newBody = `updated body`
  const updateBodyArgs = {commentId: '1', body: newBody, bodyVersion: '1'}
  const mockedResponse = {
    ok: true,
    json: async (): Promise<UpdateReviewCommentMutationResponse> => ({
      body: newBody,
      bodyHTML: newBody,
      commentDatabaseId: 15,
      threadId: 15,
    }),
  }

  mockFetch.mockRouteOnce(/update_review_comment\?body_version=1/, updateBodyArgs, mockedResponse)

  const {result} = renderHook(() => useUpdateReviewCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate(updateBodyArgs)

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)
  expect(markersData).toBeDefined()
  const thread = markersData?.threads[15]
  expect(thread).toBeUndefined()
  expectMockFetchCalledTimes(/update_review_comment/, 1)
})
