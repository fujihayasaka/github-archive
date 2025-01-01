import type {ReactNode} from 'react'
import {renderHook, waitFor} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {useChangeBaseBranchMutation} from '../use-change-base-branch-mutation'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'

jest.mock('@github-ui/fetch-utils', () => {
  return {
    fetchPoll: () => {
      return {
        json: async () => ({
          orchestration: {state: 'succeeded'},
        }),
      }
    },
  }
})

const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint', async () => {
  const newBaseBranch = 'foo'
  const newBaseBranchBinary = btoa(encodeURIComponent(newBaseBranch))
  const mockOrchestrationUrl = '/mock/orchestration'
  const mockResponse = {
    ok: true,
    json: async () => ({
      orchestration: {url: mockOrchestrationUrl},
    }),
  }
  mockFetch.mockRouteOnce(/change_base/, {new_base_binary: newBaseBranchBinary}, mockResponse)

  const {result} = renderHook(() => useChangeBaseBranchMutation(), {wrapper: withBaseProvidersWrapper(wrapper)})
  result.current.mutate({newBaseBranch})

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })
  expectMockFetchCalledTimes(/change_base/, 1)
})
