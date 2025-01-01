import {useSso} from '@github-ui/use-sso'
import {screen} from '@testing-library/react'

import {render} from '../../test-utils/Render'
import {SecurityCenterDependabotMetrics} from '../SecurityCenterDependabotMetrics'
import {getSecurityCenterDependabotMetricsProps} from '../test-utils/mock-data'

jest.mock('@github-ui/use-sso')

beforeEach(() => {
  jest.mocked(useSso).mockImplementation(() => ({ssoOrgs: [], baseAvatarUrl: ''}))
  jest.spyOn(console, 'error').mockImplementation((message: string) => {
    // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
    // * any errors that are not related to the async nature of the component.
    if (!message.includes?.('wrapped in act(')) {
      // eslint-disable-next-line no-console
      console.error(message)
    }
  })
})

afterEach(() => {
  jest.restoreAllMocks()
})

describe('SecurityCenterDependabotMetrics', () => {
  it('should render with charts', () => {
    const props = getSecurityCenterDependabotMetricsProps()
    render(<SecurityCenterDependabotMetrics {...props} />)
    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.queryByTestId('area-chart-card:alerts-in-pull-requests')).not.toBeInTheDocument()
  })

  it('should render sso selector when needed', () => {
    const ssoOrgs = [
      {id: '1', name: 'Contoso', login: 'fabrikam'},
      {id: '2', name: 'Fabrikam', login: 'fabrikam'},
    ]
    jest.mocked(useSso).mockImplementation(() => ({ssoOrgs, baseAvatarUrl: ''}))
    const props = getSecurityCenterDependabotMetricsProps()
    render(<SecurityCenterDependabotMetrics {...props} />)
    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('sso-banner')).toBeInTheDocument()
  })

  it('should render expected cards', () => {
    const props = getSecurityCenterDependabotMetricsProps()
    props.showChartFeatures = true
    render(<SecurityCenterDependabotMetrics {...props} />)

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByText('Alerts remediated')).toBeInTheDocument()
  })

  it('should not render the alerts remediated card when the showChartFeatures flag is false', () => {
    const props = getSecurityCenterDependabotMetricsProps()
    props.showChartFeatures = false
    render(<SecurityCenterDependabotMetrics {...props} />)

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.queryByText('Alerts remediated')).not.toBeInTheDocument()
  })
})
