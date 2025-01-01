import {mockFetch} from '@github-ui/mock-fetch'
import {act, waitFor} from '@testing-library/react'
import {renderHook} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import {useUpdatePullRequestBranchMutation} from '../use-update-pull-request-branch-mutation'
import {noop} from '@github-ui/noop'
import {fetchPoll} from '@github-ui/fetch-utils'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `${basePageDataURL}/page_data/${PageData.updatePullRequestBranch}`
const mergeOrchestrationURL = 'merge/orchestration'
const input = {
  updateMethod: 'squash',
  expectedHeadOid: 'abcdef1234567890abcdef1234567890abcdef12',
}
jest.mock('@github-ui/fetch-utils')
const fetchPollMock = jest.mocked(fetchPoll)

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
  test('it should call the merge API and poll from orchestration', async () => {
    // Mock the orchestration polling with success
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => {
          return {orchestration: {}}
        },
      } as Response),
    )
    const networkMock = mockFetch.mockRouteOnce(apiURL, {
      orchestration: {url: mergeOrchestrationURL},
    })

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onSuccess: noop, onError: noop}), {
      wrapper: Wrapper,
    })

    await act(async () => result.current.mutateAsync(input))
    await waitFor(() => result.current.isSuccess)
    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(networkMock).toHaveBeenCalledWith(apiURL, expect.objectContaining({body: JSON.stringify(input)}))
    expect(fetchPollMock).toHaveBeenCalledTimes(1)
  })

  test('throws error if orchestration API polling returns error message', async () => {
    // Mock the orchestration polling with failure
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: false,
        status: 500,
        json: async () => {
          return {orchestration: {error_message: 'failed orchestration polling'}}
        },
      } as Response),
    )
    const networkMock = mockFetch.mockRouteOnce(apiURL, {
      orchestration: {url: mergeOrchestrationURL},
    })
    jest.spyOn(console, 'error').mockImplementation()
    const onError = jest.fn()
    const onSuccess = jest.fn()

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onError, onSuccess}), {
      wrapper: Wrapper,
    })

    let error: Error | null = null

    try {
      await act(async () => result.current.mutateAsync(input))
    } catch (e) {
      error = e as Error
    }

    await waitFor(() => result.current.isError)

    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledWith(error)
    expect(error?.message).toBe('failed orchestration polling')
    expect(onSuccess).not.toHaveBeenCalled()
  })

  test('on error it triggers onError callback', async () => {
    const networkMock = mockFetch.mockRouteOnce(apiURL, {}, {status: 500, ok: false})
    jest.spyOn(console, 'error').mockImplementation()
    const onError = jest.fn()

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onError, onSuccess: noop}), {
      wrapper: Wrapper,
    })

    let error: Error | null = null

    try {
      await act(async () => result.current.mutateAsync(input))
    } catch (e) {
      error = e as Error
    }

    await waitFor(() => result.current.isError)

    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledWith(error)
  })

  test('on success it triggers onSuccess callback', async () => {
    // Mock the orchestration polling with success
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => {
          return {orchestration: {}}
        },
      } as Response),
    )
    const networkMock = mockFetch.mockRouteOnce(apiURL, {
      orchestration: {url: mergeOrchestrationURL},
    })
    const onSuccess = jest.fn()

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onError: noop, onSuccess}), {
      wrapper: Wrapper,
    })

    await act(async () => result.current.mutateAsync(input))
    await waitFor(() => result.current.isSuccess)

    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(onSuccess).toHaveBeenCalledTimes(1)
  })
})

describe('when :merge_box_use_fetch_with_error_handling feature is enabled', () => {
  test('it should call the merge API and poll from orchestration', async () => {
    // Mock the orchestration polling with success
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => {
          return {orchestration: {}}
        },
      } as Response),
    )
    const networkMock = mockFetch.mockRouteOnce(apiURL, {
      orchestration: {url: mergeOrchestrationURL},
    })

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onSuccess: noop, onError: noop}), {
      wrapper: WrapperWithMergeBoxUseFetchWithErrorHandlingFeature,
    })

    await act(async () => result.current.mutateAsync(input))
    await waitFor(() => result.current.isSuccess)
    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(networkMock).toHaveBeenCalledWith(apiURL, expect.objectContaining({body: JSON.stringify(input)}))
    expect(fetchPollMock).toHaveBeenCalledTimes(1)
  })

  test('throws error if orchestration API polling returns error message', async () => {
    // Mock the orchestration polling with failure
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: false,
        status: 500,
        json: async () => {
          return {orchestration: {error_message: 'failed orchestration polling'}}
        },
      } as Response),
    )
    const networkMock = mockFetch.mockRouteOnce(apiURL, {
      orchestration: {url: mergeOrchestrationURL},
    })
    jest.spyOn(console, 'error').mockImplementation()
    const onError = jest.fn()
    const onSuccess = jest.fn()

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onError, onSuccess}), {
      wrapper: WrapperWithMergeBoxUseFetchWithErrorHandlingFeature,
    })

    let error: Error | null = null

    try {
      await act(async () => result.current.mutateAsync(input))
    } catch (e) {
      error = e as Error
    }

    await waitFor(() => result.current.isError)

    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledWith(error)
    expect(error?.message).toBe('failed orchestration polling')
    expect(onSuccess).not.toHaveBeenCalled()
  })

  test('on error it triggers onError callback', async () => {
    const networkMock = mockFetch.mockRouteOnce(apiURL, {}, {status: 500, ok: false})
    jest.spyOn(console, 'error').mockImplementation()
    const onError = jest.fn()

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onError, onSuccess: noop}), {
      wrapper: WrapperWithMergeBoxUseFetchWithErrorHandlingFeature,
    })

    let error: Error | null = null

    try {
      await act(async () => result.current.mutateAsync(input))
    } catch (e) {
      error = e as Error
    }

    await waitFor(() => result.current.isError)

    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledTimes(1)
    expect(onError).toHaveBeenCalledWith(error)
  })

  test('on success it triggers onSuccess callback', async () => {
    // Mock the orchestration polling with success
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => {
          return {orchestration: {}}
        },
      } as Response),
    )
    const networkMock = mockFetch.mockRouteOnce(apiURL, {
      orchestration: {url: mergeOrchestrationURL},
    })
    const onSuccess = jest.fn()

    const {result} = renderHook(() => useUpdatePullRequestBranchMutation({onError: noop, onSuccess}), {
      wrapper: WrapperWithMergeBoxUseFetchWithErrorHandlingFeature,
    })

    await act(async () => result.current.mutateAsync(input))
    await waitFor(() => result.current.isSuccess)

    expect(networkMock).toHaveBeenCalledTimes(1)
    expect(onSuccess).toHaveBeenCalledTimes(1)
  })
})
