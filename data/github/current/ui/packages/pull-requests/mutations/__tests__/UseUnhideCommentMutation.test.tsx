import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {ReactNode} from 'react'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {mockMarkersDataWithHiddenComment} from '../../test-utils/files-changed/markers-mock-data'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {renderHook, waitFor} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {useUnhideCommentMutation} from '../use-unhide-comment-mutation'

const basePath = '/github/github/pull/3'
const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={basePath}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint and updates the expected query stores', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersDataWithHiddenComment)

  const mockedResponse = {
    ok: true,
    commentDatabaseId: 15,
    threadId: 15,
  }

  mockFetch.mockRouteOnce(/unhide_comment/, mockedResponse)

  const {result} = renderHook(() => useUnhideCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({commentDatabaseId: 15})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const unhiddenComment = markersData.threads[15]?.commentsData.comments.find(comment => comment.databaseId === 15)
  expect(unhiddenComment).toBeDefined()
  expect(unhiddenComment?.isHidden).toEqual(false)
  expectMockFetchCalledTimes(/unhide_comment/, 1)
  expect(markersData.annotations).toEqual(mockMarkersDataWithHiddenComment.annotations)
})

test('skips updating markers if the comment id is not in the list', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersDataWithHiddenComment)

  const mockedResponse = {
    ok: true,
    commentDatabaseId: 1,
    threadId: 1,
  }

  mockFetch.mockRouteOnce(/unhide_comment/, mockedResponse)

  const {result} = renderHook(() => useUnhideCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({commentDatabaseId: 1})

  await waitFor(() => {
    //false becasue the endpoint returns a 404 when it can't find an associated comment
    expect(result.current.isSuccess).toEqual(false)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const unhiddenComment = markersData.threads[15]?.commentsData.comments.find(comment => comment.databaseId === 15)
  expect(unhiddenComment).toBeDefined()
  expect(unhiddenComment?.isHidden).toEqual(true)
})

test('it handles when we have no marker data', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, undefined)

  const mockedResponse = {
    ok: true,
    commentDatabaseId: 15,
    threadId: 15,
  }

  mockFetch.mockRouteOnce(/unhide_comment/, mockedResponse)

  const {result} = renderHook(() => useUnhideCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({commentDatabaseId: 15})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  expect(queryClient.getQueryData<Markers>(markersQueryKey)).toEqual(undefined)
})
