import {render} from '@github-ui/react-core/test-utils'
import {screen, fireEvent, act} from '@testing-library/react'

import {Index} from '../routes/Index'
import {getIndexRoutePayload, mockSearchResults} from '@github-ui/marketplace-common/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

// bypass debounce for testing
jest.mock('@github/mini-throttle', () => ({
  ...jest.requireActual('@github/mini-throttle'),
  debounce: jest.fn(fn => {
    fn.cancel = jest.fn()
    fn.flush = jest.fn()
    return fn
  }),
}))

const mockVerifiedFetch = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

describe('Index', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })
  test('Renders the Index page', () => {
    const routePayload = getIndexRoutePayload()
    render(<Index />, {
      routePayload,
    })
    expect(screen.getByRole('heading', {level: 1})).toHaveTextContent('Enhance your workflow with extensions')
  })

  test('searching for a space does not fire search query', () => {
    const routePayload = getIndexRoutePayload()
    render(<Index />, {
      routePayload,
    })
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(screen.getByTestId('search-input'), {target: {value: ' '}})
    expect(mockVerifiedFetch).not.toHaveBeenCalled()
  })
  test('searching for a valid screen fires a search query', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: async () => {
        return mockSearchResults
      },
    })
    const routePayload = getIndexRoutePayload()
    render(<Index />, {
      routePayload,
    })
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(() => {
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.change(screen.getByTestId('search-input'), {target: {value: 'test'}})
    })
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/marketplace?query=test')
  })
})
