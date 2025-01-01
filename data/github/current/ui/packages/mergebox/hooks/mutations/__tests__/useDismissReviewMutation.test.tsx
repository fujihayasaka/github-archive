// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {act, waitFor} from '@testing-library/react'
import {renderHook} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {useDismissReviewMutation} from '../use-dismiss-review-mutation'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'

const basePageDataURL = '/github/github/pull/3'
const apiURL = `${basePageDataURL}/page_data/dismiss_review`
const dismissReviewInput = {
  reviewId: 123,
  message: 'Dismissed by user',
}

beforeEach(() => {
  jest.clearAllMocks()
})

function wrapper({children}: {children: React.ReactNode}) {
  return <PageDataContextProvider basePageDataUrl={basePageDataURL}>{children}</PageDataContextProvider>
}

test('it should call the dismiss review API and invalidate Merge Box Query data', async () => {
  const networkMock = mockFetch.mockRouteOnce(apiURL)
  const queryClientSpy = jest.spyOn(getQueryClient(), 'invalidateQueries')
  const {result} = renderHook(() => useDismissReviewMutation(), {
    wrapper,
  })

  await act(async () => result.current.mutateAsync(dismissReviewInput))
  await waitFor(() => result.current.isSuccess)
  expect(networkMock).toHaveBeenCalledTimes(1)
  expect(queryClientSpy).toHaveBeenCalledWith(
    {queryKey: [PageData.mergeBox, `basePageDataURL:${basePageDataURL}`]},
    {cancelRefetch: false},
  )
})
