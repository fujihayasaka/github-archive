import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {ReactNode} from 'react'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {pullRequestMarkersKey, type Markers} from '../../page-data/loaders/use-markers-data'
import {mockMarkersData} from '../../test-utils/files-changed/markers-mock-data'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {renderHook, waitFor} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {useReactToCommentMutation} from '../use-react-to-comment-mutation'
import type {ReactionViewerGroup} from '@github-ui/reaction-viewer/ReactionGroupsUtils'

const basePath = '/github/github/pull/3'
const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={basePath}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint for adding a reaction', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)

  const mockedResponse: {
    reactionGroups: ReactionViewerGroup[]
  } = {
    reactionGroups: [
      {
        reaction: {
          content: 'HEART',
          viewerHasReacted: true,
        },
        reactors: [{typeName: 'User', login: 'monalisa'}],
        totalCount: 1,
      },
    ],
  }

  mockFetch.mockRouteOnce(/add_comment_reaction/, mockedResponse)

  const {result} = renderHook(() => useReactToCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate({commentDatabaseId: 15, threadId: '15', reaction: 'heart', viewerHasReacted: false})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!
  const updatedComment = markersData.threads['15']!.commentsData.comments.find(comment => comment.databaseId === 15)

  expect(updatedComment).toBeDefined()
  expect(updatedComment?.reactionGroups).toEqual(mockedResponse.reactionGroups)
  expect(markersData.annotations).toEqual(mockMarkersData.annotations)
})

test('it makes a request to the expected endpoint for removing a reaction', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)

  const mockedResponse: {
    reactionGroups: ReactionViewerGroup[]
  } = {
    reactionGroups: [
      {
        reaction: {
          content: 'HEART',
          viewerHasReacted: false,
        },
        reactors: [],
        totalCount: 0,
      },
    ],
  }

  mockFetch.mockRouteOnce(/remove_comment_reaction/, mockedResponse)

  const {result} = renderHook(() => useReactToCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate({commentDatabaseId: 15, threadId: '15', reaction: 'heart', viewerHasReacted: true})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!
  const updatedComment = markersData.threads['15']!.commentsData.comments.find(comment => comment.databaseId === 15)

  expect(updatedComment).toBeDefined()
  expect(updatedComment?.reactionGroups).toEqual(mockedResponse.reactionGroups)
})

test('skips updating markers if the comment id is not in the list', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = pullRequestMarkersKey(basePath)
  queryClient.setQueryData<Markers>(markersQueryKey, mockMarkersData)

  const mockedResponse: {
    reactionGroups: ReactionViewerGroup[]
  } = {
    reactionGroups: [
      {
        reaction: {
          content: 'HEART',
          viewerHasReacted: true,
        },
        reactors: [{typeName: 'User', login: 'monalisa'}],
        totalCount: 1,
      },
    ],
  }

  mockFetch.mockRouteOnce(/add_comment_reaction/, mockedResponse)

  const {result} = renderHook(() => useReactToCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate({commentDatabaseId: 1, threadId: '1', reaction: 'heart', viewerHasReacted: false})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const markersData = queryClient.getQueryData<Markers>(markersQueryKey)!
  expect(markersData).toEqual(mockMarkersData)

  const unchangedComment = markersData.threads['15']!.commentsData.comments.find(comment => comment.databaseId === 15)
  expect(unchangedComment).toBeDefined()
  expect(unchangedComment?.reactionGroups).toBeUndefined()
})

test('it handles when we have no marker data', async () => {
  const queryClient = getQueryClient()

  const markersQueryKey = [PageData.markers, basePath]
  queryClient.setQueryData<Markers>(markersQueryKey, undefined)

  const mockedResponse: {
    reactionGroups: ReactionViewerGroup[]
  } = {
    reactionGroups: [
      {
        reaction: {
          content: 'HEART',
          viewerHasReacted: true,
        },
        reactors: [{typeName: 'User', login: 'monalisa'}],
        totalCount: 1,
      },
    ],
  }

  mockFetch.mockRouteOnce(/add_comment_reaction/, mockedResponse)

  const {result} = renderHook(() => useReactToCommentMutation(basePath), {
    wrapper: withBaseProvidersWrapper(wrapper),
  })

  result.current.mutate({commentDatabaseId: 15, threadId: '15', reaction: 'heart', viewerHasReacted: false})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  expect(queryClient.getQueryData<Markers>(markersQueryKey)).toEqual(undefined)
})
