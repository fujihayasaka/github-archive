import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {ReactNode} from 'react'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {generateMockComment, generateMockThread} from '../../test-utils/files-changed/markers-mock-data'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {renderHook, waitFor} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {useBlockUserFromOrgMutation} from '../use-block-user-from-org-mutation'

const basePath = '/github/github/pull/3'
const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={basePath}>{children}</PageDataContextProvider>
)

const blockedMockMarkersData: Markers = {
  threads: {
    15: generateMockThread({
      comments: [
        generateMockComment({viewerCanBlockFromOrg: true}),
        generateMockComment({authorLogin: 'otheruser', viewerCanBlockFromOrg: true}),
      ],
      id: '15',
      isOutdated: false,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    }),
    1: {
      commentsData: {
        comments: [generateMockComment({viewerCanBlockFromOrg: true})],
      },
      id: '1',
      isOutdated: false,
      isResolved: false,
      viewerCanReply: false,
      subjectType: 'LINE',
    },
  },
  annotations: {},
}

test('it makes a request to the expected endpoint and updates all comments by the user', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, blockedMockMarkersData)

  const mockedResponse = {ok: true}
  mockFetch.mockRouteOnce(/blocked_users/, mockedResponse)

  const {result} = renderHook(() => useBlockUserFromOrgMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({
    duration: '7',
    hiddenReason: undefined,
    organizationLogin: 'github',
    notifyBlockedUser: true,
    shouldHideComment: false,
    userLogin: 'mockuser',
  })

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const blockedUserComments = Object.values(markersData.threads).flatMap(
    thread => thread.commentsData?.comments.filter(comment => comment.author?.login === 'mockuser') || [],
  )
  expect(blockedUserComments).toHaveLength(2)
  expect(blockedUserComments[0]?.viewerCanBlockFromOrg).toEqual(false)
  expect(blockedUserComments[0]?.viewerCanUnblockFromOrg).toEqual(true)
  expect(blockedUserComments[0]?.isHidden).toEqual(false)
  expect(blockedUserComments[0]?.minimizedReason).toBeNull()

  // Ensure the other user's comment remains unchanged
  const otherUserComments = Object.values(markersData.threads).flatMap(
    thread => thread.commentsData?.comments.filter(comment => comment.author?.login === 'otheruser') || [],
  )
  expect(otherUserComments).toHaveLength(1)
  expect(otherUserComments[0]?.viewerCanBlockFromOrg).toEqual(true)
  expect(otherUserComments[0]?.viewerCanUnblockFromOrg).toEqual(false)
  expect(otherUserComments[0]?.isHidden).toEqual(false)
  expect(otherUserComments[0]?.minimizedReason).toBeNull()

  expectMockFetchCalledTimes(/blocked_users/, 1)
})

test('it updates the comments with the correct hidden reason and visibility', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, blockedMockMarkersData)

  const mockedResponse = {ok: true}
  mockFetch.mockRouteOnce(/blocked_users/, mockedResponse)

  const {result} = renderHook(() => useBlockUserFromOrgMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({
    duration: '7',
    hiddenReason: 'SPAM',
    organizationLogin: 'github',
    notifyBlockedUser: true,
    shouldHideComment: true,
    userLogin: 'mockuser',
  })

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const blockedUserComments = Object.values(markersData.threads).flatMap(
    thread => thread.commentsData?.comments.filter(comment => comment.author?.login === 'mockuser') || [],
  )
  expect(blockedUserComments).toHaveLength(2)
  expect(blockedUserComments[0]?.viewerCanBlockFromOrg).toEqual(false)
  expect(blockedUserComments[0]?.viewerCanUnblockFromOrg).toEqual(true)
  expect(blockedUserComments[0]?.isHidden).toEqual(true)
  expect(blockedUserComments[0]?.minimizedReason).toEqual('SPAM')

  // Ensure the other user's comment remains unchanged
  const otherUserComments = Object.values(markersData.threads).flatMap(
    thread => thread.commentsData?.comments.filter(comment => comment.author?.login === 'otheruser') || [],
  )
  expect(otherUserComments).toHaveLength(1)
  expect(otherUserComments[0]?.viewerCanBlockFromOrg).toEqual(true)
  expect(otherUserComments[0]?.viewerCanUnblockFromOrg).toEqual(false)
  expect(otherUserComments[0]?.isHidden).toEqual(false)
  expect(otherUserComments[0]?.minimizedReason).toBeNull()

  expectMockFetchCalledTimes(/blocked_users/, 1)
})

test('it skips updating markers if the user is not in the list', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, blockedMockMarkersData)

  const mockedResponse = {ok: true}
  mockFetch.mockRouteOnce(/blocked_users/, mockedResponse)

  const {result} = renderHook(() => useBlockUserFromOrgMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({
    duration: '7',
    hiddenReason: 'SPAM',
    organizationLogin: 'github',
    notifyBlockedUser: true,
    shouldHideComment: true,
    userLogin: 'nonexistentuser',
  })

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!

  const blockedUserComments = Object.values(markersData.threads).flatMap(
    thread => thread.commentsData?.comments.filter(comment => comment.author?.login === 'nonexistentuser') || [],
  )
  expect(blockedUserComments).toHaveLength(0)
  expectMockFetchCalledTimes(/blocked_users/, 1)
})

it('handles when we have no markers data', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, undefined)

  const mockedResponse = {ok: true}
  mockFetch.mockRouteOnce(/blocked_users/, mockedResponse)

  const {result} = renderHook(() => useBlockUserFromOrgMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })
  result.current.mutate({
    duration: '7',
    hiddenReason: 'SPAM',
    organizationLogin: 'github',
    notifyBlockedUser: true,
    shouldHideComment: true,
    userLogin: 'mockuser',
  })

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  expect(queryClient.getQueryData<Markers>(markersQueryKey)).toBeUndefined()
})
