import {fireEvent, render, screen} from '@testing-library/react'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {EnterpriseServerSummary} from '../EnterpriseServerSummary'
import {getEnterpriseServerSummaryProps} from '../../test-utils/mock-data'

const analyticsMetadata = {}
const renderEnterpriseCloudSummary = (overrideProps = {}) => {
  return render(
    <AnalyticsProvider appName={'test-app'} category="test-analytics-category" metadata={analyticsMetadata}>
      <EnterpriseServerSummary {...getEnterpriseServerSummaryProps()} {...overrideProps} />
    </AnalyticsProvider>,
  )
}

describe('EnterpriseCloudSummary Component', () => {
  test('Shows message for non-server users', () => {
    renderEnterpriseCloudSummary({hasEnterpriseServer: false})
    expect(
      screen.getByText(
        "You don't have any server licenses or instances. Download a new license in the Enterprise Server license keys section.",
      ),
    ).toBeInTheDocument()
  })

  test('Shows message for fully matched case', () => {
    renderEnterpriseCloudSummary({ghesLicenseCount: 0})
    expect(
      screen.getByText(
        'All your server users are matched with your cloud users! See Enterprise Cloud to view your license usage.',
      ),
    ).toBeInTheDocument()
  })

  test('Adds up total usage: GHES only', () => {
    renderEnterpriseCloudSummary({
      ghesLicenseCount: 1000,
      ghesBillableLicenseCount: 1000,
      ghesUnitPrice: 2,
    })
    expect(screen.getByText('$2,000.00')).toBeInTheDocument()
  })

  test('Adds up total usage: bundled GHAS', () => {
    renderEnterpriseCloudSummary({
      ghesLicenseCount: 1000,
      bundledGhasLicenseCount: 500,
      ghesBillableLicenseCount: 1000,
      bundledGhasBillableLicenseCount: 500,
      ghesUnitPrice: 2,
      bundledGhasUnitPrice: 10,
    })
    expect(screen.getByText('$7,000.00')).toBeInTheDocument()
  })

  test('Adds up total usage: split GHAS', () => {
    renderEnterpriseCloudSummary({
      ghesLicenseCount: 1000,
      codeSecurityLicenseCount: 500,
      secretProtectionLicenseCount: 10,
      ghesBillableLicenseCount: 1000,
      codeSecurityBillableLicenseCount: 500,
      secretProtectionBillableLicenseCount: 10,
      ghesUnitPrice: 2,
      codeSecurityUnitPrice: 10,
      secretProtectionUnitPrice: 2,
    })
    expect(screen.getByText('$7,020.00')).toBeInTheDocument()
  })

  test('GHES only line item.', () => {
    renderEnterpriseCloudSummary({
      ghesLicenseCount: 1000,
      ghesBillableLicenseCount: 1000,
      ghesUnitPrice: 2,
    })

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('details'))
    expect(screen.getByText('$2/month each')).toBeInTheDocument()
  })

  test('Bundled GHAS line items.', () => {
    renderEnterpriseCloudSummary({
      ghesLicenseCount: 1000,
      bundledGhasLicenseCount: 500,
      ghesBillableLicenseCount: 1000,
      bundledGhasBillableLicenseCount: 500,
      ghesUnitPrice: 2,
      bundledGhasUnitPrice: 10,
    })

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('details'))
    expect(screen.getByText('$2/month each')).toBeInTheDocument()
    expect(screen.getByText('$10/month each')).toBeInTheDocument()
  })

  test('Split GHAS line items.', () => {
    renderEnterpriseCloudSummary({
      ghesLicenseCount: 1000,
      codeSecurityLicenseCount: 500,
      secretProtectionLicenseCount: 10,
      ghesBillableLicenseCount: 1000,
      codeSecurityBillableLicenseCount: 500,
      secretProtectionBillableLicenseCount: 10,
      ghesUnitPrice: 2,
      codeSecurityUnitPrice: 10,
      secretProtectionUnitPrice: 70000000,
    })

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('details'))
    expect(screen.getByText('$2/month each')).toBeInTheDocument()
    expect(screen.getByText('$10/month each')).toBeInTheDocument()
    expect(screen.getByText('$70,000,000/month each')).toBeInTheDocument()
  })
})
