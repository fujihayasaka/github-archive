import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageLimitsBanner, type PageLimitsBannerProps} from '../components/PageLimitsBanner'
import {getFilesRoutePayload} from '../test-utils/files-changed/files-mock-data'
import {screen} from '@testing-library/react'
import type {PageLimits} from '../page-data/payloads/files'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import {verifiedFetch} from '@github-ui/verified-fetch'

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch')

function TestComponent({...props}: PageLimitsBannerProps) {
  return (
    <FeatureFlagProvider features={{}}>
      <PageLimitsBanner {...props} />
    </FeatureFlagProvider>
  )
}
describe('PageLimitsBanner', () => {
  it('renders when the review threads limit has been exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const pageLimits: PageLimits = {
      ...filesPayload.pageLimits,
      filesLimit: 300,
      filesLimitExceeded: false,
      reviewThreadsLimit: 40,
      reviewThreadsLimitExceeded: true,
    }
    const urls = filesPayload.urls

    renderWithClient(<TestComponent pageLimits={pageLimits} repository={filesPayload.repository} urls={urls} />)
    expect(screen.getByText(/Only the first 40 comments are currently being shown/)).toBeInTheDocument()
  })

  it('renders when the annotations limit has been exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const pageLimits: PageLimits = {
      ...filesPayload.pageLimits,
      filesLimitExceeded: false,
      reviewThreadsLimitExceeded: false,
      annotationsLimit: 50,
      annotationsLimitExceeded: true,
    }
    const urls = filesPayload.urls

    renderWithClient(<TestComponent pageLimits={pageLimits} repository={filesPayload.repository} urls={urls} />)
    expect(screen.getByText(/Only the first 50 alerts are currently being shown/)).toBeInTheDocument()
  })

  it('renders the correct message when two limits are exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const pageLimits: PageLimits = {
      ...filesPayload.pageLimits,
      filesLimitExceeded: false,
      reviewThreadsLimit: 40,
      reviewThreadsLimitExceeded: true,
      annotationsLimit: 50,
      annotationsLimitExceeded: true,
    }
    const urls = filesPayload.urls

    renderWithClient(<TestComponent pageLimits={pageLimits} repository={filesPayload.repository} urls={urls} />)
    expect(screen.getByText(/Only the first 40 comments and 50 alerts are currently being shown/)).toBeInTheDocument()
  })

  it('renders the correct message when three limits are exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const pageLimits: PageLimits = {
      ...filesPayload.pageLimits,
      filesLimit: 300,
      filesLimitExceeded: true,
      reviewThreadsLimit: 40,
      reviewThreadsLimitExceeded: true,
      annotationsLimit: 50,
      annotationsLimitExceeded: true,
    }
    const urls = filesPayload.urls

    renderWithClient(<TestComponent pageLimits={pageLimits} repository={filesPayload.repository} urls={urls} />)
    expect(
      screen.getByText(/Only the first 300 files, 40 comments, and 50 alerts are currently being shown/),
    ).toBeInTheDocument()
  })

  it('does not render when the files limit has not been exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const pageLimits: PageLimits = {
      ...filesPayload.pageLimits,
      filesLimit: 300,
      filesLimitExceeded: false,
    }
    const urls = filesPayload.urls

    renderWithClient(<TestComponent pageLimits={pageLimits} repository={filesPayload.repository} urls={urls} />)
    expect(screen.queryByText(/Only the first 300 files are currently being shown/)).not.toBeInTheDocument()
  })

  it('toggles feature preview when the switch back link is clicked', async () => {
    const mockVerifiedFetch = jest.mocked(verifiedFetch)
    mockVerifiedFetch.mockResolvedValue(new Response())

    const filesPayload = getFilesRoutePayload()
    const pageLimits: PageLimits = {
      ...filesPayload.pageLimits,
      filesLimit: 300,
      filesLimitExceeded: true,
    }
    const urls = filesPayload.urls

    const {user} = renderWithClient(
      <TestComponent pageLimits={pageLimits} repository={filesPayload.repository} urls={urls} />,
    )

    const switchBackLink = screen.getByText('switch back')
    await user.click(switchBackLink)

    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      expect.stringContaining('/toggle_generic_feature'),
      expect.objectContaining({
        body: expect.any(FormData),
        method: 'POST',
      }),
    )

    // Verify FormData contains the correct feature name
    const fetchCallOptions = mockVerifiedFetch.mock.calls?.[0]?.[1]
    const formDataArg = fetchCallOptions?.body as FormData
    expect(formDataArg.get('feature_name')).toBe('prx_files')
  })
})
