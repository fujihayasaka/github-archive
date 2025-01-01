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

  test('When hasMeteredGhe is false, does not show GHE line item (with bundled GHAS)', () => {
    renderEnterpriseCloudSummary({
      hasMeteredGhe: false,
      bundledGhasLicenseCount: 500,
      bundledGhasBillableLicenseCount: 500,
      bundledGhasUnitPrice: 10,
    })

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('details'))
    expect(screen.queryByText('$2/month each')).not.toBeInTheDocument()
    expect(screen.getByText('$10/month each')).toBeInTheDocument()
  })

  test('When hasMeteredGhe is false, does not show GHE line item (with split GHAS)', () => {
    renderEnterpriseCloudSummary({
      hasMeteredGhe: false,
      codeSecurityLicenseCount: 500,
      codeSecurityBillableLicenseCount: 500,
      codeSecurityUnitPrice: 10,
      secretProtectionLicenseCount: 10,
      secretProtectionBillableLicenseCount: 10,
      secretProtectionUnitPrice: 70000000,
    })

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('details'))
    expect(screen.queryByText('$2/month each')).not.toBeInTheDocument()
    expect(screen.getByText('$10/month each')).toBeInTheDocument()
    expect(screen.getByText('$70,000,000/month each')).toBeInTheDocument()
  })

  test('Shows seat counts for metered GHE and bundled GHAS', () => {
    renderEnterpriseCloudSummary({
      hasMeteredGhe: true,
      ghesLicenseCount: 1000,
      ghesBillableLicenseCount: 1000,
      ghesUnitPrice: 2,
      bundledGhasLicenseCount: 500,
      bundledGhasBillableLicenseCount: 500,
      bundledGhasUnitPrice: 10,
    })

    const gheSeatCountEl = screen.getByTestId('seat-count-ghe')
    expect(gheSeatCountEl).toBeInTheDocument()
    expect(gheSeatCountEl).toHaveTextContent('1,000')

    const bundledGhasSeatCountEl = screen.getByTestId('seat-count-advanced-security')
    expect(bundledGhasSeatCountEl).toBeInTheDocument()
    expect(bundledGhasSeatCountEl).toHaveTextContent('500')
  })

  test('Shows seat counts for metered GHE and split GHAS', () => {
    renderEnterpriseCloudSummary({
      hasMeteredGhe: true,
      ghesLicenseCount: 1000,
      ghesBillableLicenseCount: 1000,
      ghesUnitPrice: 2,
      codeSecurityLicenseCount: 500,
      codeSecurityBillableLicenseCount: 500,
      codeSecurityUnitPrice: 10,
      secretProtectionLicenseCount: 10,
      secretProtectionBillableLicenseCount: 10,
      secretProtectionUnitPrice: 70000000,
    })

    const gheSeatCountEl = screen.getByTestId('seat-count-ghe')
    expect(gheSeatCountEl).toBeInTheDocument()
    expect(gheSeatCountEl).toHaveTextContent('1,000')

    const codeSecuritySeatCountEl = screen.getByTestId('seat-count-code-security')
    expect(codeSecuritySeatCountEl).toBeInTheDocument()
    expect(codeSecuritySeatCountEl).toHaveTextContent('500')

    const secretProtectionSeatCountEl = screen.getByTestId('seat-count-secret-protection')
    expect(secretProtectionSeatCountEl).toBeInTheDocument()
    expect(secretProtectionSeatCountEl).toHaveTextContent('10')
  })

  test('Shows correct seat counts for no GHE and bundled GHAS', () => {
    renderEnterpriseCloudSummary({
      hasMeteredGhe: false,
      bundledGhasLicenseCount: 500,
      bundledGhasBillableLicenseCount: 500,
      bundledGhasUnitPrice: 10,
    })

    const gheSeatCountEl = screen.queryByTestId('seat-count-ghe')
    expect(gheSeatCountEl).not.toBeInTheDocument()

    const bundledGhasSeatCountEl = screen.getByTestId('seat-count-advanced-security')
    expect(bundledGhasSeatCountEl).toBeInTheDocument()
    expect(bundledGhasSeatCountEl).toHaveTextContent('500')
  })

  test('Shows correct seat counts for no GHE and split GHAS', () => {
    renderEnterpriseCloudSummary({
      hasMeteredGhe: false,
      codeSecurityLicenseCount: 500,
      codeSecurityBillableLicenseCount: 500,
      codeSecurityUnitPrice: 10,
      secretProtectionLicenseCount: 10,
      secretProtectionBillableLicenseCount: 10,
      secretProtectionUnitPrice: 70000000,
    })

    const gheSeatCountEl = screen.queryByTestId('seat-count-ghe')
    expect(gheSeatCountEl).not.toBeInTheDocument()

    const codeSecuritySeatCountEl = screen.getByTestId('seat-count-code-security')
    expect(codeSecuritySeatCountEl).toBeInTheDocument()
    expect(codeSecuritySeatCountEl).toHaveTextContent('500')

    const secretProtectionSeatCountEl = screen.getByTestId('seat-count-secret-protection')
    expect(secretProtectionSeatCountEl).toBeInTheDocument()
    expect(secretProtectionSeatCountEl).toHaveTextContent('10')
  })
})
