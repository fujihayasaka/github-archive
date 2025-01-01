import {screen, act} from '@testing-library/react'
import {render, setupUserEvent, RouteContext} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {RequestState} from '../components/RequestState'
import {exampleRequest} from './helpers'

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return jest.fn().mockImplementation(() => {
      return {origin: 'https://github.localhost', pathname: exampleRequest.repoExemptionsBaseUrl!}
    })()
  },
}))

const requesterProps = {
  request: exampleRequest,
  responses: [],
  rulesets: exampleRequest.rulesetNames.map((name, index) => ({
    id: index + 1,
    name,
    url: `rules/${index + 1}`,
  })),
  isRequester: true,
}

const reviewerProps = {
  ...requesterProps,
  isRequester: false,
}

test('renders RequestState as a requester', () => {
  render(<RequestState {...requesterProps} />)

  const createdStatus = screen.getByText('submitted a bypass request')
  expect(createdStatus).toBeVisible()

  const cancelButton = screen.getByRole('button', {name: 'Cancel request'})
  expect(cancelButton).toBeVisible()

  const approvalRequiredStatus = screen.getAllByText('Approval required')
  expect(approvalRequiredStatus).toHaveLength(2)
})

test('renders RequestState as a reviewer', () => {
  render(<RequestState {...reviewerProps} />)

  const createdStatus = screen.getByText('submitted a bypass request')
  expect(createdStatus).toBeVisible()

  const cancelButton = screen.queryByRole('button', {name: 'Cancel request'})
  expect(cancelButton).not.toBeInTheDocument()

  const approvalRequiredStatus = screen.getAllByText('Approval required')
  expect(approvalRequiredStatus).toHaveLength(2)
})

test('cancels request with the correct url', async () => {
  render(<RequestState {...requesterProps} />)
  const userEvent = setupUserEvent()

  const cancelButton = screen.getByRole('button', {name: 'Cancel request'})
  expect(cancelButton).toBeVisible()

  await userEvent.click(cancelButton)
  expect(mockFetch.fetch).toHaveBeenCalledTimes(1)
  await act(() => {
    mockFetch.resolvePendingRequest(exampleRequest.repoExemptionsBaseUrl!, {ok: true})
  })

  expect(RouteContext.location?.search).toEqual('?cancel=')
})
