import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotSummarizeBannerLoader} from '../CopilotSummarizeBannerLoader'
import {verifiedFetch} from '@github-ui/verified-fetch'

const mockVerifiedFetch = verifiedFetch as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

beforeEach(async () => {
  jest.resetAllMocks()
})

test('loads the specified banner', async () => {
  mockVerifiedFetch.mockResolvedValue({
    status: 200,
    ok: true,
    text: async () => '<p>A very nice piece of content indeed.</p>',
  })
  const bannerPath = '/some/github/endpoint'

  render(<CopilotSummarizeBannerLoader bannerPath={bannerPath} />)

  await act(() => {
    expect(mockVerifiedFetch).toHaveBeenCalled()
    expect(mockVerifiedFetch).toHaveBeenCalledWith(bannerPath, {headers: {Accept: 'text/html'}, method: 'GET'})
  })

  expect(screen.getByText('A very nice piece of content indeed.')).toBeInTheDocument()
})

test('renders nothing when banner request is not successful', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    status: 404,
    text: async () => '<p>This page did not load</p>',
  })
  const bannerPath = '/some/github/endpoint'

  render(<CopilotSummarizeBannerLoader bannerPath={bannerPath} />)

  await act(() => {
    expect(mockVerifiedFetch).toHaveBeenCalled()
    expect(mockVerifiedFetch).toHaveBeenCalledWith(bannerPath, {headers: {Accept: 'text/html'}, method: 'GET'})
  })

  expect(screen.queryByText('This page did not load')).not.toBeInTheDocument()
})
