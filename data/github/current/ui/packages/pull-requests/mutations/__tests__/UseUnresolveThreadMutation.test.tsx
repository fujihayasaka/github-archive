import {getQueryClient} from '@github-ui/react-core/query-client'

import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {ReactNode} from 'react'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {mockMarkersData} from '../../test-utils/files-changed/markers-mock-data'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {useUnresolveThreadMutation} from '../use-unresolve-thread-mutation'
import {renderHook, waitFor} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'

const basePath = '/github/github/pull/3'
const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={basePath}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint and updates expected query stores', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)

  const resolvedThread = mockMarkersData.threads[15]!
  const mockResolvedMarkersData: Markers = {
    ...mockMarkersData,
    threads: {
      ...mockMarkersData.threads,
      15: {
        ...resolvedThread,
        isResolved: true,
        commentsData: resolvedThread.commentsData || {comments: []},
      },
    },
  }

  queryClient.setQueryData<Markers>(markersQueryKey, mockResolvedMarkersData)

  const mockedResponse = {
    ok: true,
  }

  mockFetch.mockRouteOnce(/unresolve_thread/, {threadId: '15'}, mockedResponse)

  const {result} = renderHook(() => useUnresolveThreadMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({threadId: '15'})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const thread = markersData.threads[15]
  expect(thread?.isResolved).toEqual(false)
  expectMockFetchCalledTimes(/unresolve_thread/, 1)
  expect(markersData.annotations).toEqual(mockResolvedMarkersData.annotations)
})

test('skips updating markers if the thread id is not in the list', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  const resolvedThread = mockMarkersData.threads[15]!
  const mockResolvedMarkersData: Markers = {
    ...mockMarkersData,
    threads: {
      ...mockMarkersData.threads,
      15: {
        ...resolvedThread,
        isResolved: true,
        commentsData: resolvedThread.commentsData || {comments: []},
      },
    },
  }

  queryClient.setQueryData<Markers>(markersQueryKey, mockResolvedMarkersData)

  const mockedResponse = {
    ok: true,
  }

  mockFetch.mockRouteOnce(/unresolve_thread/, {threadId: '15'}, mockedResponse)

  const {result} = renderHook(() => useUnresolveThreadMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({threadId: '1'})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })
  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const thread = markersData.threads[15]
  expect(thread?.isResolved).toEqual(true)

  expectMockFetchCalledTimes(/unresolve_thread/, 1)
  expect(queryClient.getQueryData<Markers>(markersQueryKey)).toEqual(markersData)
})

test('it handles when we have no marker data', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, undefined)

  const mockedResponse = {
    ok: true,
  }

  mockFetch.mockRouteOnce(/unresolve_thread/, {threadId: '15'}, mockedResponse)

  const {result} = renderHook(() => useUnresolveThreadMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({threadId: '15'})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  expect(queryClient.getQueryData<Markers>(markersQueryKey)).toEqual(undefined)
})
