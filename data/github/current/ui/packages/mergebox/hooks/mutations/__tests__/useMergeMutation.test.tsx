import {mockFetch} from '@github-ui/mock-fetch'
import {act, waitFor} from '@testing-library/react'
import {renderHook} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {useMergeMutation} from '../use-merge-mutation'
import {noop} from '@github-ui/noop'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `${basePageDataURL}/page_data/merge`
const mergeData = {
  authorEmail: 'monalisa',
  commitMessage: 'additional data about the commit',
  commitTitle: 'shipping a fix',
  mergeMethod: 'rebase',
  bypassBranchProtections: false,
}

beforeEach(() => {
  jest.clearAllMocks()
})

function Wrapper({children}: {children: React.ReactNode}) {
  return <PageDataContextProvider basePageDataUrl={basePageDataURL}>{children}</PageDataContextProvider>
}

function WrapperWithMergeBoxUseFetchWithErrorHandlingFeature({children}: {children: React.ReactNode}) {
  return (
    <FeatureFlagProvider features={{merge_box_use_fetch_with_error_handling: true}}>
      <Wrapper>{children}</Wrapper>
    </FeatureFlagProvider>
  )
}

describe('when :merge_box_use_fetch_with_error_handling is disabled', () => {
  test('it should call the merge API and invalidate Merge Box Query data', async () => {
    const networkMock = mockFetch.mockRouteOnce(apiURL)
    const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')

    const {result} = renderHook(() => useMergeMutation({onError: noop}), {wrapper: Wrapper})

    await act(async () => result.current.mutateAsync(mergeData))
    await waitFor(() => result.current.isSuccess)
    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(networkMock).toHaveBeenCalledWith(apiURL, expect.objectContaining({body: JSON.stringify(mergeData)}))
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

    const {result} = renderHook(() => useMergeMutation({onError}), {
      wrapper: Wrapper,
    })

    let error: Error | null = null

    try {
      await act(async () => result.current.mutateAsync(mergeData))
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
})

describe('when :merge_box_use_fetch_with_error_handling feature is enabled', () => {
  test('it should call the merge API and invalidate Merge Box Query data', async () => {
    const networkMock = mockFetch.mockRouteOnce(apiURL)
    const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')

    const {result} = renderHook(() => useMergeMutation({onError: noop}), {
      wrapper: WrapperWithMergeBoxUseFetchWithErrorHandlingFeature,
    })

    await act(async () => result.current.mutateAsync(mergeData))
    await waitFor(() => result.current.isSuccess)
    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(networkMock).toHaveBeenCalledWith(apiURL, expect.objectContaining({body: JSON.stringify(mergeData)}))
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

    const {result} = renderHook(() => useMergeMutation({onError}), {
      wrapper: WrapperWithMergeBoxUseFetchWithErrorHandlingFeature,
    })

    let error: Error | null = null

    try {
      await act(async () => result.current.mutateAsync(mergeData))
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
})
