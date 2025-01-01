import {
  getLicensingAdvancedSecuritySummaryProps,
  getSelfServeSubscriptionInfo,
  getSelfServeTrialInfo,
  skus,
} from '../../test-utils/mock-data'
import {screen} from '@testing-library/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {LicensingAdvancedSecuritySummary} from '../LicensingAdvancedSecuritySummary'
import {render} from '@github-ui/react-core/test-utils'

const renderLicensingAdvancedSecuritySummary = (overrideProps = {}, stafftools = false, isTeams = false) => {
  return render(
    <NavigationContextProvider
      isTeams={isTeams}
      enterpriseContactUrl={'/enterprise-contact-url'}
      isStafftools={stafftools}
      slug={'test-co'}
    >
      <LicensingAdvancedSecuritySummary {...getLicensingAdvancedSecuritySummaryProps()} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('LicensingAdvancedSecuritySummary Component', () => {
  test('renders the summary UI when isAdvancedSecurityEnabled is true', () => {
    renderLicensingAdvancedSecuritySummary({
      skus: [{...skus[0], consumedLicenses: 30}],
      isSelfServeAdvancedSecurity: true,
    })

    const summaryHeaderTitleEl = screen.queryByTestId('usage-summary-header-title')
    expect(summaryHeaderTitleEl).toBeInTheDocument()
    expect(summaryHeaderTitleEl).toHaveTextContent('Consumed licenses')

    const consumedLicensesAmountEl = screen.queryByTestId('summary-item-amount')
    expect(consumedLicensesAmountEl).toBeInTheDocument()
    expect(consumedLicensesAmountEl).toHaveTextContent('30')
  })

  test('does not render the summary UI when isAdvancedSecurityEnabled is false', () => {
    renderLicensingAdvancedSecuritySummary({consumedLicenses: 30, isAdvancedSecurityEnabled: false})

    const consumedLicensesHeaderEl = screen.queryByTestId('usage-summary-header')
    expect(consumedLicensesHeaderEl).not.toBeInTheDocument()
  })

  test('renders the usage exceeded banner when volume usage exceeds the limit', () => {
    const message = 'You are using 15 Code Security licenses, exceeding the limit of 10.'
    renderLicensingAdvancedSecuritySummary({usageExceededMessage: message})

    const exceededBannerEl = screen.getByTestId('usage-exceeded-banner')
    expect(exceededBannerEl).toBeInTheDocument()
    expect(exceededBannerEl).toHaveTextContent(message)
  })

  test('renders the usage at capacity banner when volume usage is at capacity', () => {
    const message = 'You are at capacity for your Secret Protection licenses.'
    renderLicensingAdvancedSecuritySummary({usageAtCapacityMessage: message})

    const atCapacityBannerEl = screen.getByTestId('usage-at-capacity-banner')
    expect(atCapacityBannerEl).toBeInTheDocument()
    expect(atCapacityBannerEl).toHaveTextContent(message)
  })
})

describe('LicensingAdvancedSecuritySummary ServerLicensesFooter', () => {
  const secretProtectionSku = skus.find(sku => sku.sku === 'secret-protection')
  const codeSecuritySku = skus.find(sku => sku.sku === 'code-security')

  test('does not render ServerLicensesFooter for metered licensed', () => {
    renderLicensingAdvancedSecuritySummary({
      isMeteredLicensed: true,
      skus: [{...skus[0], serverOnlyConsumedLicenses: 5}],
    })

    const footerEl = screen.queryByTestId('server-licenses-footer')
    expect(footerEl).not.toBeInTheDocument()
  })

  test('renders ServerLicensesFooter for the bundled sku', () => {
    renderLicensingAdvancedSecuritySummary({
      isMeteredLicensed: false,
      skus: [{...skus[0], serverOnlyConsumedLicenses: 5}],
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent('Additional users from GitHub Connect: 5 for Advanced Security')
  })

  test('renders ServerLicensesFooter for the unbundled secret-protection sku', () => {
    renderLicensingAdvancedSecuritySummary({
      isMeteredLicensed: false,
      isBundled: false,
      skus: [{...secretProtectionSku, serverOnlyConsumedLicenses: 5}],
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent('Additional users from GitHub Connect: 5 for Secret Protection')
  })

  test('renders ServerLicensesFooter for the unbundled code-security sku', () => {
    renderLicensingAdvancedSecuritySummary({
      isMeteredLicensed: false,
      isBundled: false,
      skus: [{...codeSecuritySku, serverOnlyConsumedLicenses: 5}],
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent('Additional users from GitHub Connect: 5 for Code Security')
  })

  test('renders ServerLicensesFooter for both unbundled skus', () => {
    renderLicensingAdvancedSecuritySummary({
      isMeteredLicensed: false,
      isBundled: false,
      skus: [
        {
          ...secretProtectionSku,
          serverOnlyConsumedLicenses: 10,
        },
        {
          ...codeSecuritySku,
          serverOnlyConsumedLicenses: 5,
        },
      ],
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent(
      'Additional users from GitHub Connect: 10 for Secret Protection, 5 for Code Security',
    )
  })
})

describe('LicensingAdvancedSecuritySummary pending plan change', () => {
  test('renders the pending plan change banner when one is present', () => {
    renderLicensingAdvancedSecuritySummary({
      isSelfServeAdvancedSecurity: true,
      selfServeSubscriptionInfo: getSelfServeSubscriptionInfo(),
    })

    expect(screen.getByTestId('pending-plan-change')).toBeInTheDocument()
  })

  test('does not render the pending plan change banner when one is not present', () => {
    renderLicensingAdvancedSecuritySummary({
      isSelfServeAdvancedSecurity: true,
      getSelfServeSubscriptionInfo: {
        ...getSelfServeSubscriptionInfo(),
        pendingCycleChange: null,
      },
    })

    expect(screen.queryByTestId('pending-plan-change')).not.toBeInTheDocument()
  })
})

describe('LicensingAdvancedSecuritySummary self-serve trial', () => {
  test('shows the start trial when eligible', () => {
    renderLicensingAdvancedSecuritySummary({
      eligibleForTrial: true,
    })

    expect(screen.getByTestId('start-trial-button')).toBeInTheDocument()
    expect(screen.queryByTestId('csv-downloader-button')).not.toBeInTheDocument()
  })

  test('does not show the start trial when not eligible', () => {
    renderLicensingAdvancedSecuritySummary({
      eligibleForTrial: false,
    })

    expect(screen.queryByTestId('start-trial-button')).not.toBeInTheDocument()
  })

  test('clicking start trial button opens the start trial dialog', async () => {
    const {user} = renderLicensingAdvancedSecuritySummary({
      eligibleForTrial: true,
      selfServeTrialInfo: getSelfServeTrialInfo(),
    })

    const startTrialButton = screen.getByTestId('start-trial-button')
    expect(startTrialButton).toBeInTheDocument()

    await user.click(startTrialButton)

    expect(screen.getByRole('dialog', {name: 'Start your free 30 day trial'})).toBeInTheDocument()
  })
})

describe('LicensingAdvancedSecuritySummary teams', () => {
  const secretProtectionSku = skus.find(sku => sku.sku === 'secret-protection')

  test('renders the CSV button for teams billable usage when isTeams is true and there is usage', () => {
    renderLicensingAdvancedSecuritySummary(
      {
        skus: [
          {
            ...secretProtectionSku,
            billableLicenses: 1,
            consumedLicenses: 0,
          },
        ],
      },
      false,
      true,
    )

    expect(screen.getByTestId('csv-downloader-button')).toBeInTheDocument()
  })

  test('renders the CSV button for teams consumed usage when isTeams is true and there is usage', () => {
    renderLicensingAdvancedSecuritySummary(
      {
        skus: [
          {
            ...secretProtectionSku,
            consumedLicenses: 1,
            billableLicenses: 0,
          },
        ],
      },
      false,
      true,
    )

    expect(screen.getByTestId('csv-downloader-button')).toBeInTheDocument()
  })

  test('does not render the CSV button for teams usage when isTeams is true and there is usage', () => {
    renderLicensingAdvancedSecuritySummary(
      {
        skus: [
          {
            ...secretProtectionSku,
            consumedLicenses: 0,
            billableLicenses: 0,
          },
        ],
      },
      false,
      true,
    )

    expect(screen.queryByTestId('csv-downloader-button')).not.toBeInTheDocument()
  })
})
