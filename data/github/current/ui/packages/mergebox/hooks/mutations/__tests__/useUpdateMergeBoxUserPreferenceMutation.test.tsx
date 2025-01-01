// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {noop} from '@github-ui/noop'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {renderHook} from '@github-ui/react-core/test-utils'
import {act, waitFor} from '@testing-library/react'
import {useUpdateMergeBoxUserPreferenceMutation} from '../use-update-merge-box-user-preference'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `${basePageDataURL}/page_data/update_merge_box_user_preference`

beforeEach(() => {
  jest.clearAllMocks()
})

function wrapper({children}: {children: React.ReactNode}) {
  return <PageDataContextProvider basePageDataUrl={basePageDataURL}>{children}</PageDataContextProvider>
}

const bodyData = {
  preferenceName: 'status_checks_grouping_preference',
  preference: 'grouped_by_status',
}

test('it should call the merge box user preference API and invalidate Merge Box Query data', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL)
  const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')

  const {result} = renderHook(() => useUpdateMergeBoxUserPreferenceMutation({onError: noop}), {
    wrapper,
  })

  await act(async () => result.current.mutateAsync(bodyData))
  await waitFor(() => result.current.isSuccess)

  expect(networkMock).toHaveBeenCalledTimes(1)
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

  const {result} = renderHook(() => useUpdateMergeBoxUserPreferenceMutation({onError}), {
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

describe('Validation logic in useUpdateMergeBoxUserPreferenceMutation', () => {
  const onError = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('throws an error if preferenceName or preference is missing', async () => {
    const {result} = renderHook(() => useUpdateMergeBoxUserPreferenceMutation({onError}), {wrapper})

    await expect(act(async () => result.current.mutateAsync({preferenceName: '', preference: ''}))).rejects.toThrow(
      'Preference name and value must be provided.',
    )
  })

  test('throws an error if preferenceName is invalid', async () => {
    const {result} = renderHook(() => useUpdateMergeBoxUserPreferenceMutation({onError}), {wrapper})

    await expect(
      act(async () =>
        result.current.mutateAsync({preferenceName: 'invalid_preference', preference: 'grouped_by_status'}),
      ),
    ).rejects.toThrow('Invalid preference name.')
  })

  test('throws an error if preference value is invalid', async () => {
    const {result} = renderHook(() => useUpdateMergeBoxUserPreferenceMutation({onError}), {wrapper})

    await expect(
      act(async () =>
        result.current.mutateAsync({preferenceName: 'status_checks_grouping_preference', preference: 'invalid_value'}),
      ),
    ).rejects.toThrow('Invalid preference value.')
  })
})
