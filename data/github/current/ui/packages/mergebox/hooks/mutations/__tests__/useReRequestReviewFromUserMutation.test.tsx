// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {act, waitFor} from '@testing-library/react'
import {renderHook} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {useReRequestReviewFromUser} from '../use-re-request-review-from-user'
import {noop} from '@github-ui/noop'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `${basePageDataURL}/page_data/re_request_review_from_user`
const bodyData = {
  reviewerLogin: 'monalisa',
}

beforeEach(() => {
  jest.clearAllMocks()
})

function wrapper({children}: {children: React.ReactNode}) {
  return <PageDataContextProvider basePageDataUrl={basePageDataURL}>{children}</PageDataContextProvider>
}

test('it should call the rerequest review from user API and invalidate Merge Box Query data', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL)
  const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')

  const {result} = renderHook(() => useReRequestReviewFromUser({onError: noop}), {
    wrapper,
  })

  await act(async () => result.current.mutateAsync(bodyData))
  await waitFor(() => result.current.isSuccess)
  expect(networkMock).toHaveBeenCalledTimes(1)
  expect(networkMock).toHaveBeenCalledWith(apiURL, expect.objectContaining({body: JSON.stringify(bodyData)}))
  expect(queryClientSpy).toHaveBeenCalledWith(
    {queryKey: [PageData.mergeBox, `basePageDataURL:${basePageDataURL}`]},
    {cancelRefetch: false},
  )
})

test('on error it triggers onError callback', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL, {}, {status: 500, ok: false})
  jest.spyOn(console, 'error').mockImplementation()
  const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')
  const onError = jest.fn()

  const {result} = renderHook(() => useReRequestReviewFromUser({onError}), {
    wrapper,
  })

  let error: Error | null = null

  try {
    await act(async () => result.current.mutateAsync(bodyData))
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
