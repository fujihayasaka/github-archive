// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {ReactNode} from 'react'

import {renderHook, waitFor} from '@testing-library/react'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {useUpdateTitleMutation} from '../use-update-title-mutation'
import {getHeaderPageData} from '../../test-utils/header-mock-data'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import type {HeaderPageData} from '../../page-data/payloads/header'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {getQueryClient} from '@github-ui/react-core/query-client'

const wrapper = ({children}: {children: ReactNode}) => (
  <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>{children}</PageDataContextProvider>
)

test('it makes a request to the expected endpoint', async () => {
  const queryClient = getQueryClient()
  const {
    pullRequest: {number, title},
  } = getHeaderPageData()

  const headerQueryKey = [PageData.header, `basePageDataURL:${BASE_PAGE_DATA_URL}`]
  queryClient.setQueryData(headerQueryKey, {pullRequest: {title}})

  const newTitle = `${title}-updated`
  const updateTitleArgs = {id: number, title: newTitle}
  const mockedResponse = {
    ok: true,
    json: async () => ({
      pullRequest: {title: newTitle},
    }),
  }

  mockFetch.mockRouteOnce(/update_title/, updateTitleArgs, mockedResponse)

  const {result} = renderHook(() => useUpdateTitleMutation(), {wrapper: withBaseProvidersWrapper(wrapper)})
  result.current.mutate(updateTitleArgs)

  await waitFor(() => {
    expect(result.current.isSuccess).toEqual(true)
  })

  const headerData = queryClient.getQueryData<HeaderPageData>(headerQueryKey)!
  expect(headerData.pullRequest.title).toEqual(newTitle)
  expectMockFetchCalledTimes(/update_title/, 1)
})
