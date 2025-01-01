import FailureBanner, {type FailureBannerProps} from '../components/FailureBanner'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ENABLEMENT_FAILURES_MAP} from '../utils/helpers'
import App from '../App'
import {defaultAppContext} from '../test-utils/mock-data'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {swallowCSSParsingError} from '../test-utils/test-helper'

const mockCloseFn = jest.fn()
const mockUpdateQuery = jest.fn()
const defaultProps = {
  closeFn: mockCloseFn,
  updateQuery: mockUpdateQuery,
  failureCounts: {'of an unknown reason': 1},
}

function failureBanner(props: FailureBannerProps) {
  return (
    <App>
      <FailureBanner {...props} />
    </App>
  )
}

describe('FailureBanner', () => {
  beforeEach(swallowCSSParsingError)

  beforeEach(() => {
    mockCloseFn.mockClear()
    mockUpdateQuery.mockClear()
  })

  it('does not render if failureCounts is empty', async () => {
    const props = {...defaultProps, failureCounts: {}}
    render(failureBanner(props))

    // Use queryByTestId so we don't fail when the element isn't found:
    const element = screen.queryByTestId('failure-banner')
    expect(element).not.toBeInTheDocument()
  })

  it('calls closeFn when the X is clicked', async () => {
    const {user} = render(failureBanner(defaultProps), {routePayload: defaultAppContext()})
    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/dismiss_failure_banner',
      {},
      {ok: true, status: 201},
    )

    const dismissButton = screen.getByLabelText('Dismiss banner')
    await user.click(dismissButton)
    expect(mockCloseFn).toHaveBeenCalled()
  })

  it('renders one failure when only one is passed', async () => {
    render(failureBanner(defaultProps))

    const element = screen.getByTestId('failure-banner')
    expect(element).toHaveTextContent(
      '1 repository failed to apply because of an unknown reason. View all failed repositories.',
    )
  })

  it('renders multiple failure as separate lines', async () => {
    const failureCounts = {
      'of an unknown reason': 1,
      'of an Enterprise policy': 2,
      'of a code scanning conflict': 999,
    }
    const props = {...defaultProps, failureCounts}
    render(failureBanner(props))

    const element = screen.getByTestId('failure-banner')
    expect(element).toHaveTextContent('1002 repositories failed to apply:')
    expect(element).toHaveTextContent('1 repository failed because of an unknown reason.')
    expect(element).toHaveTextContent('2 repositories failed because of an Enterprise policy.')
    expect(element).toHaveTextContent('999 repositories failed because of a code scanning conflict')
    expect(element).toHaveTextContent('View all failed repositories')
  })

  it('sets the search query to `config-status:failed` when `View all failed repositories` is clicked', async () => {
    const {user} = render(failureBanner(defaultProps))

    const link = screen.getByText('View all failed repositories')
    await user.click(link)
    expect(mockUpdateQuery).toHaveBeenCalled()
  })

  // This test is meant to ensure that the ENABLEMENT_FAILURES_MAP always contains a frontend_banner_reason.
  // If you're seeing a failure here it might be because you updated the ENABLEMENT_FAILURES_MAP and did not add a
  // frontend_banner_reason. Please add one so nothing breaks. :) <3
  it('ENABLEMENT_FAILURES_MAP has frontend_banner_reason definitions for all failures!', async () => {
    const mapKeys = new Set(ENABLEMENT_FAILURES_MAP.keys())
    for (const key of mapKeys) {
      const bannerMapValue: {frontend_banner_reason?: string} | undefined = ENABLEMENT_FAILURES_MAP.get(key)
      expect(bannerMapValue).toBeTruthy()
      expect(bannerMapValue!['frontend_banner_reason']!).toBeTruthy()
    }
  })
})
