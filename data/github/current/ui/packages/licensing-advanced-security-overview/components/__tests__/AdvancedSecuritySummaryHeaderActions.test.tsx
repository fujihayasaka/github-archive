import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ThemeProvider} from '@primer/react'

import {AdvancedSecuritySummaryHeaderActions} from '../AdvancedSecuritySummaryHeaderActions'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {skus} from '../../test-utils/mock-data'

const renderAdvancedSecuritySummaryHeaderActions = (overrideProps = {}, stafftools = false, teams = false) => {
  const defaultProps = {
    skus: [],
    isSelfServeAdvancedSecurity: true,
    onManageSeatsSelect: jest.fn(),
    onCancelSubscriptionSelect: jest.fn(),
    buyButtonPath: '',
    configureButtonPath: '',
    teamsUsage: false,
    isTeams: false,
    isStafftools: false,
    eligibleForTrial: false,
    onFreeTrialClick: jest.fn(),
  }
  return render(
    <ThemeProvider>
      <NavigationContextProvider
        enterpriseContactUrl={'/enterprise-contact-url'}
        isStafftools={stafftools}
        slug={'test-co'}
        isTeams={teams}
      >
        <AdvancedSecuritySummaryHeaderActions {...defaultProps} {...overrideProps} />
      </NavigationContextProvider>
    </ThemeProvider>,
  )
}

describe('AdvancedSecuritySummaryHeaderActions Component', () => {
  describe('Free Trial Button', () => {
    test('renders free trial button when eligible for trial', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        eligibleForTrial: true,
        selfServeTrialInfo: {trialDays: 30},
      })

      const trialButtonEl = screen.getByTestId('start-trial-button')
      expect(trialButtonEl).toBeInTheDocument()
      expect(trialButtonEl).toHaveTextContent('Try free for 30 days')
    })
  })

  describe('CSV download', () => {
    describe('render button', () => {
      test('with full menu (no early return conditions)', () => {
        renderAdvancedSecuritySummaryHeaderActions({
          skus: skus.filter(sku => sku.sku === 'bundled'),
        })

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
        expect(csvDownloadButtonEl).toHaveAttribute(
          'href',
          '/enterprises/test-co/enterprise_licensing/download_active_committers',
        )
        expect(csvDownloadButtonEl).toHaveTextContent('Download CSV report')
      })

      test('when trial is active', () => {
        renderAdvancedSecuritySummaryHeaderActions(
          {
            skus: skus.filter(sku => sku.sku === 'bundled'),
            trialInfo: {isActive: true, expirationDate: new Date()},
            buyButtonPath: '/buy',
          },
          true,
        )

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
      })

      test('with invoice license info', () => {
        renderAdvancedSecuritySummaryHeaderActions(
          {
            skus: skus.filter(sku => sku.sku === 'bundled'),
            invoiceLicenseInfo: {
              actionType: 'renewal',
            },
          },
          true,
        )

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
      })

      test('when not self-serve', () => {
        renderAdvancedSecuritySummaryHeaderActions(
          {
            skus: skus.filter(sku => sku.sku === 'bundled'),
            isSelfServeAdvancedSecurity: false,
          },
          true,
        )

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
      })

      test('with teams route', () => {
        renderAdvancedSecuritySummaryHeaderActions({skus: skus.filter(sku => sku.sku === 'bundled')}, false, true)

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
        expect(csvDownloadButtonEl).toHaveAttribute('href', '/organizations/test-co/download_active_committers')
        expect(csvDownloadButtonEl).toHaveTextContent('Download CSV report')
      })

      test('in stafftools route', () => {
        renderAdvancedSecuritySummaryHeaderActions({skus: skus.filter(sku => sku.sku === 'bundled')}, true)

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
        expect(csvDownloadButtonEl).toHaveAttribute(
          'href',
          '/stafftools/enterprises/test-co/advanced_security/download_active_committers',
        )
        expect(csvDownloadButtonEl).toHaveTextContent('Download CSV report')
      })

      test('with teams route even in stafftools', () => {
        renderAdvancedSecuritySummaryHeaderActions({skus: skus.filter(sku => sku.sku === 'bundled')}, true, true)

        const csvDownloadButtonEl = screen.getByTestId('csv-downloader-button')
        expect(csvDownloadButtonEl).toBeInTheDocument()
        expect(csvDownloadButtonEl).toHaveAttribute('href', '/organizations/test-co/download_active_committers')
        expect(csvDownloadButtonEl).toHaveTextContent('Download CSV report')
      })
    })

    describe('does not render button', () => {
      test('when trial has expired', () => {
        renderAdvancedSecuritySummaryHeaderActions(
          {
            skus: skus.filter(sku => sku.sku === 'bundled'),
            trialInfo: {isActive: false, expirationDate: new Date()},
          },
          true,
        )

        expect(screen.queryByTestId('csv-downloader-button')).not.toBeInTheDocument()
      })

      test('does not render button for teams', () => {
        renderAdvancedSecuritySummaryHeaderActions(
          {
            skus: skus.filter(sku => sku.sku === 'bundled'),
            isSelfServeAdvancedSecurity: true,
            isTeams: true,
          },
          true,
        )

        expect(screen.queryByTestId('csv-downloader-button')).not.toBeInTheDocument()
      })

      test('when eligible for trial', () => {
        renderAdvancedSecuritySummaryHeaderActions(
          {
            skus: skus.filter(sku => sku.sku === 'bundled'),
            eligibleForTrial: true,
          },
          true,
        )

        expect(screen.queryByTestId('csv-downloader-button')).not.toBeInTheDocument()
      })
    })
  })

  describe('configure button', () => {
    test('renders configure button', () => {
      const {user} = renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        configureButtonPath: '/buy',
        isTeams: true,
      })

      const configureButtonEl = screen.getByTestId('advanced-security-configure-button')
      expect(configureButtonEl).toBeInTheDocument()
      expect(configureButtonEl).toHaveTextContent('Configure')

      user.click(configureButtonEl)
    })

    test('does not render configure button on stafftools', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        configureButtonPath: '/buy',
        isTeams: true,
        isStafftools: true,
      })

      expect(screen.queryByTestId('advanced-security-configure-button')).not.toBeInTheDocument()
    })

    test('does not render if buy button path prop is missing', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        isTeams: true,
      })

      expect(screen.queryByTestId('advanced-security-configure-button')).not.toBeInTheDocument()
    })

    test('does not render if not teams', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        buyButtonPath: '/buy',
        isTeams: false,
      })

      expect(screen.queryByTestId('advanced-security-configure-button')).not.toBeInTheDocument()
    })
  })

  describe('buy advanced security button', () => {
    test('render when trial is active & buy path provided', () => {
      const {user} = renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        trialInfo: {isActive: true, expirationDate: new Date()},
        buyButtonPath: '/buy',
      })

      const trialButtonEl = screen.getByTestId('buy-advanced-security-button')
      expect(trialButtonEl).toBeInTheDocument()
      expect(trialButtonEl).toHaveTextContent('Buy Advanced Security')

      user.click(trialButtonEl)
    })

    test('render when trial has expired', () => {
      const {user} = renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        trialInfo: {isActive: false, expirationDate: new Date()},
        buyButtonPath: '/buy',
      })

      const trialButtonEl = screen.getByTestId('buy-advanced-security-button')
      expect(trialButtonEl).toBeInTheDocument()
      expect(trialButtonEl).toHaveTextContent('Buy Advanced Security')

      user.click(trialButtonEl)
    })

    test('does not render if buy button path prop is missing', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        isSelfServeAdvancedSecurity: true,
        trialInfo: {isActive: false, expirationDate: new Date()},
      })

      expect(screen.queryByTestId('buy-advanced-security-button')).not.toBeInTheDocument()
    })
  })

  describe('invoiced business', () => {
    test('renders contact sales button', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        invoiceLicenseInfo: {
          statusMessage: {
            variant: 'critical',
          },
        },
      })

      const invoiceRenewalButtonEl = screen.getByTestId('contact-sales-button')
      expect(invoiceRenewalButtonEl).toBeInTheDocument()
      expect(invoiceRenewalButtonEl).toHaveTextContent('Contact sales')
    })

    test('renders renew button', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        invoiceLicenseInfo: {
          actionType: 'renewal',
        },
      })

      const invoiceRenewalButtonEl = screen.getByTestId('renew-button')
      expect(invoiceRenewalButtonEl).toBeInTheDocument()
      expect(invoiceRenewalButtonEl).toHaveTextContent('Renew Advanced Security')
    })

    test('renders upgrade button', () => {
      renderAdvancedSecuritySummaryHeaderActions({
        skus: skus.filter(sku => sku.sku === 'bundled'),
        invoiceLicenseInfo: {
          actionType: 'upgrade',
        },
      })

      const invoiceRenewalButtonEl = screen.getByTestId('upgrade-button')
      expect(invoiceRenewalButtonEl).toBeInTheDocument()
      expect(invoiceRenewalButtonEl).toHaveTextContent('Add licenses')
    })
  })
})
