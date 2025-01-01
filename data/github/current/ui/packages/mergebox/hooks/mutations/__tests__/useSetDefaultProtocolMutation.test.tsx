// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {act, waitFor} from '@testing-library/react'
import {renderHook} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useSetDefaultProtocol} from '../use-set-default-protocol-mutation'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `/push-protocol`
const baseRefName = 'main'

beforeEach(() => {
  jest.clearAllMocks()
})

function wrapper({children}: {children: React.ReactNode}) {
  return <PageDataContextProvider basePageDataUrl={basePageDataURL}>{children}</PageDataContextProvider>
}

test('it should call the set default protocol API and invalidates Merge Box Query data', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL)
  const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')

  const {result} = renderHook(() => useSetDefaultProtocol(baseRefName), {
    wrapper,
  })

  await act(async () => result.current.mutateAsync(apiURL))
  await waitFor(() => result.current.isSuccess)
  expect(networkMock).toHaveBeenCalledTimes(1)
  expect(queryClientSpy).toHaveBeenCalledWith(
    {queryKey: [PageData.mergeInstructions, `basePageDataURL:${basePageDataURL}`, `baseRefName:${baseRefName}`]},
    {cancelRefetch: false},
  )
})
