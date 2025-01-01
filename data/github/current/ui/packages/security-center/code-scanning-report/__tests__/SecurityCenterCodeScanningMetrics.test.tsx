import {useSso} from '@github-ui/use-sso'
import {screen} from '@testing-library/react'

import {render} from '../../test-utils/Render'
import {SecurityCenterCodeScanningMetrics} from '../SecurityCenterCodeScanningMetrics'
import {getSecurityCenterCodeScanningMetricsProps} from '../test-utils/mock-data'

jest.mock('@github-ui/use-sso')

beforeEach(() => {
  jest.mocked(useSso).mockImplementation(() => ({ssoOrgs: [], baseAvatarUrl: ''}))
})

describe('SecurityCenterCodeScanningMetrics', () => {
  it('should render with charts', () => {
    const props = getSecurityCenterCodeScanningMetricsProps()
    render(<SecurityCenterCodeScanningMetrics {...props} />)
    expect(screen.getByText('CodeQL pull request alerts')).toBeInTheDocument()
    expect(screen.queryByTestId('area-chart-card:alerts-in-pull-requests')).not.toBeInTheDocument()
    expect(screen.getByTestId('bar-chart-card:remediation-rates')).toBeInTheDocument()
    expect(screen.getByTestId('column-chart-card:alerts-in-pull-requests')).toBeInTheDocument()
  })

  it('should render with explicit date range', () => {
    const props = getSecurityCenterCodeScanningMetricsProps()
    props.initialDateSpan = {from: '2021-01-01', to: '2021-12-31'}
    render(<SecurityCenterCodeScanningMetrics {...props} />)
    expect(screen.getByText('CodeQL pull request alerts')).toBeInTheDocument()
  })

  it('should render sso selector when needed', () => {
    const ssoOrgs = [
      {id: '1', name: 'Contoso', login: 'fabrikam'},
      {id: '2', name: 'Fabrikam', login: 'fabrikam'},
    ]
    jest.mocked(useSso).mockImplementation(() => ({ssoOrgs, baseAvatarUrl: ''}))
    const props = getSecurityCenterCodeScanningMetricsProps()
    render(<SecurityCenterCodeScanningMetrics {...props} />)
    expect(screen.getByText('CodeQL pull request alerts')).toBeInTheDocument()
    expect(screen.getByTestId('sso-banner')).toBeInTheDocument()
  })

  it('should render export button', () => {
    const props = getSecurityCenterCodeScanningMetricsProps()
    render(<SecurityCenterCodeScanningMetrics {...props} />)
    expect(screen.getByText('Export CSV')).toBeInTheDocument()
  })

  it('should render expected cards', () => {
    const props = getSecurityCenterCodeScanningMetricsProps()
    render(<SecurityCenterCodeScanningMetrics {...props} />)

    expect(screen.getByText('Alerts found')).toBeInTheDocument()
    expect(screen.getByText('Copilot Autofix suggestions')).toBeInTheDocument()
    expect(screen.getByText('Alerts fixed')).toBeInTheDocument()
    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByText('Alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByText('Remediation rates')).toBeInTheDocument()
    expect(screen.getByText('Most prevalent rules')).toBeInTheDocument()
  })

  describe('when autofix feature is not available', () => {
    it('should render expected cards', () => {
      const props = getSecurityCenterCodeScanningMetricsProps()
      props.allowAutofixFeatures = false
      render(<SecurityCenterCodeScanningMetrics {...props} />)

      expect(screen.getByText('Alerts found')).toBeInTheDocument()
      expect(screen.queryByText('Copilot Autofix suggestions')).not.toBeInTheDocument()
      expect(screen.getByText('Alerts fixed')).toBeInTheDocument()
      expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
      expect(screen.queryByText('Alerts fixed with autofix suggestions')).not.toBeInTheDocument()
      expect(screen.queryByText('Remediation rates')).not.toBeInTheDocument()
      expect(screen.getByText('Most prevalent rules')).toBeInTheDocument()
    })
  })

  describe('when csv export is not available', () => {
    it('should not render export button', () => {
      const props = getSecurityCenterCodeScanningMetricsProps()
      props.allowCsvExport = false

      render(<SecurityCenterCodeScanningMetrics {...props} />)
      expect(screen.queryByText('Export CSV')).not.toBeInTheDocument()
    })
  })
})
