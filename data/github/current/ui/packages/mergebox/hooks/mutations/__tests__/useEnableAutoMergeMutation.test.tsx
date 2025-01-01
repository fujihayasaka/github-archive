// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {act, waitFor} from '@testing-library/react'
import {renderHook} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useEnableAutoMergeMutation} from '../use-enable-auto-merge-mutation'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `${basePageDataURL}/page_data/enable_auto_merge`
const enableAutoMergeInput = {
  authorEmail: 'monalisa',
  commitMessage: 'additional commit info',
  commitTitle: 'making a commit',
  mergeMethod: 'squash',
}

beforeEach(() => {
  jest.clearAllMocks()
})

function wrapper({children}: {children: React.ReactNode}) {
  return <PageDataContextProvider basePageDataUrl={basePageDataURL}>{children}</PageDataContextProvider>
}

test('it should call the enable auto merge API and refetch Merge Box Query data', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL)
  const queryClientSpy = jest.spyOn(getQueryClient(), 'refetchQueries')

  const {result} = renderHook(() => useEnableAutoMergeMutation(), {
    wrapper,
  })

  await act(async () => result.current.mutateAsync(enableAutoMergeInput))
  await waitFor(() => result.current.isSuccess)
  expect(networkMock).toHaveBeenCalledTimes(1)
  expect(networkMock).toHaveBeenCalledWith(
    apiURL,
    expect.objectContaining({body: JSON.stringify(enableAutoMergeInput)}),
  )
  expect(queryClientSpy).toHaveBeenCalledWith(
    {queryKey: [PageData.mergeBox, `basePageDataURL:${basePageDataURL}`]},
    {cancelRefetch: false},
  )
})

test('on error it triggers onError callback', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL, {}, {status: 500, ok: false})
  jest.spyOn(console, 'error').mockImplementation()
  const queryClientSpy = jest.spyOn(getQueryClient(), 'refetchQueries')
  const onError = jest.fn()

  const {result} = renderHook(() => useEnableAutoMergeMutation({onError}), {
    wrapper,
  })

  let error: Error | null = null

  try {
    await act(async () => result.current.mutateAsync(enableAutoMergeInput))
  } catch (e) {
    error = e as Error
  }

  await waitFor(() => result.current.isError)

  expect(networkMock).toHaveBeenCalledTimes(1)
  expect(onError).toHaveBeenCalledTimes(1)
  expect(onError).toHaveBeenCalledWith(error)
  expect(queryClientSpy).not.toHaveBeenCalledWith(
    {queryKey: [PageData.mergeBox, `basePageDataURL:${basePageDataURL}`]},
    {cancelRefetch: false},
  )
})

test('on success it triggers onSuccess callback', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL)
  const onSuccess = jest.fn()

  const {result} = renderHook(() => useEnableAutoMergeMutation({onSuccess}), {
    wrapper,
  })

  await act(async () => result.current.mutateAsync(enableAutoMergeInput))
  await waitFor(() => result.current.isSuccess)

  expect(networkMock).toHaveBeenCalledTimes(1)
  expect(onSuccess).toHaveBeenCalledTimes(1)
})
