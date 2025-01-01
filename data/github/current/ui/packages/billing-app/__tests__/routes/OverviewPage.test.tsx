import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor} from '@testing-library/react'
import {ENTERPRISE_ORG_OWNER, MEMBER, OWNER} from '../../constants'
import {OverviewPage} from '../../routes/'
import {
  getOverviewPayloadForUsers,
  getOverviewRoutePayload,
  getOverviewRoutePayloadWithAdminRole,
  getOverviewRoutePayloadWithEmptyAlert,
  getOverviewRoutePayloadWithMultipleAlerts,
  getUsageRoutePayloadWithPrepaidCredits,
  MOCK_LINE_ITEMS,
} from '../../test-utils/mock-data'
import {PageContext} from '../../App'
import useUsageChartData from '../../hooks/usage/use-usage-chart-data'
import type {UsageChartData} from '../../types/usage'
import {RequestState} from '../../enums'

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return jest.fn().mockImplementation(() => {
      return {origin: 'https://github.localhost', pathname: '/enterprises/github-inc/billing'}
    })()
  },
}))

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => {
    return {business: 'github-inc'}
  },
}))

jest.mock('../../hooks/usage/use-usage-chart-data')
jest.mocked(useUsageChartData).mockReturnValue({
  usageChartData: MOCK_LINE_ITEMS.map(item => ({...item, data: []})) as UsageChartData[],
  requestState: RequestState.IDLE,
})

describe('Overview page', () => {
  it('Renders the Overview page', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )

    const headings = await screen.findAllByRole('heading')
    const headingTexts = headings.map(h => h.textContent)
    expect(headingTexts).toEqual(
      expect.arrayContaining([
        'Overview',
        'Current metered usage',
        'Metered usage',
        'Usage by organization',
        'Usage by repository',
        'Products selector navigation',
        'Actions usage',
      ]),
    )
  })

  it('Renders the Overview page with a budget alert banner', async () => {
    const routePayload = getOverviewRoutePayload()
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.getByTestId('billing-banner')).toHaveTextContent("You've used 100%"))
  })

  it('Renders the Overview page without a budget alert banner', async () => {
    const routePayload = getOverviewRoutePayloadWithEmptyAlert()
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.queryByTestId('billing-banner')).not.toBeInTheDocument())
  })

  it('Renders the Overview page with multiple budget alert banners', async () => {
    const routePayload = getOverviewRoutePayloadWithMultipleAlerts()
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.getAllByTestId('billing-banner')).toHaveLength(2))
  })

  it('Hides the prepaid credits tile when prepaid credits disabled or does not exist', async () => {
    const routePayload = getOverviewRoutePayload()
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.queryByTestId('prepaid-credits-card')).not.toBeInTheDocument())
  })

  it('Shows the prepaid credits tile when prepaid credits is enabled and credits exist', async () => {
    const routePayload = getUsageRoutePayloadWithPrepaidCredits()
    render(<OverviewPage />, {routePayload})
    await waitFor(() =>
      expect(screen.queryByTestId('prepaid-credits-card')).toHaveTextContent(
        'You have $45.80 remaining in prepaid credits. Contact GitHub sales or your reseller/distributor to increase the balance',
      ),
    )
  })

  it('Hides the payment due tile when showPaymentDueTile disabled', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.showPaymentDueTile = false
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.queryByTestId('auto-pay-enabled-payment-due-card')).not.toBeInTheDocument())
  })

  it('Shows the payment due tile when showPaymentDueTile enabled', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.showPaymentDueTile = true
    render(<OverviewPage />, {routePayload})
    expect(await screen.findByTestId('auto-pay-enabled-payment-due-card')).toBeInTheDocument()
  })

  it('Hides the volume spend tile when show_volume_license_spend_tile disabled', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.showVolumeLicenseSpendTile = false
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.queryByTestId('volume-licenses-card')).not.toBeInTheDocument())
  })

  it('Shows the volume spend tile when show_volume_license_spend_tile enabled', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.showVolumeLicenseSpendTile = true
    render(<OverviewPage />, {routePayload})
    expect(await screen.findByTestId('volume-licenses-card-combined')).toBeInTheDocument()
  })

  it('Does not show the budgets section for a trial customer', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.customer.plan = 'enterprise_trial'
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<OverviewPage />, {routePayload})
      await waitFor(() => expect(screen.queryByTestId('budgets-section')).not.toBeInTheDocument())
    })
  })

  it('Hides the sales tax disclaimer when taxDisclaimer is blank', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.taxDisclaimer = ''
    render(<OverviewPage />, {routePayload})
    await waitFor(() => expect(screen.queryByTestId('sales-tax-disclaimer-fineprint')).not.toBeInTheDocument())
  })

  it('Shows the sales tax disclaimer when taxDisclaimer is present (US)', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.taxDisclaimer = 'US'
    render(<OverviewPage />, {routePayload})
    expect(await screen.findByTestId('sales-tax-disclaimer-fineprint')).toBeInTheDocument()
  })

  it('Shows the JCT tax disclaimer when taxDisclaimer is present (JP)', async () => {
    const routePayload = getOverviewRoutePayload()
    routePayload.taxDisclaimer = 'JP'
    render(<OverviewPage />, {routePayload})
    expect(await screen.findByTestId('sales-tax-disclaimer-fineprint')).toBeInTheDocument()
  })

  it('Shows the "Usage by organization" tile on enterprise view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('org-usage-card')).toBeInTheDocument()
  })

  it('Hides the "Usage by organization" tile on org view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: true, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    await waitFor(() => expect(screen.queryByTestId('org-usage-card')).not.toBeInTheDocument())
  })

  it('Shows the "Subscriptions" section on org view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: true, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('billing-subscriptions-section')).toBeInTheDocument()
  })

  it('Shows the "Current plan" tile on org view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: true, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('current-plan-card')).toBeInTheDocument()
  })

  it('Hides the "Current plan" tile on enterprise view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    await waitFor(() => expect(screen.queryByTestId('current-plan-card')).not.toBeInTheDocument())
  })

  it('Properly renders for User customers', async () => {
    const routePayload = getOverviewPayloadForUsers()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: false, isUserRoute: true}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('billing-subscriptions-section')).toBeInTheDocument()
  })

  it('Renders the current included usage section for enterprise org owners', async () => {
    const routePayload = getOverviewRoutePayloadWithAdminRole(ENTERPRISE_ORG_OWNER)
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('total-discount')).toBeInTheDocument()
  })

  it('Renders the current included usage section for enterprise owners', async () => {
    const routePayload = getOverviewRoutePayloadWithAdminRole(OWNER)
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('total-discount')).toBeInTheDocument()
  })

  it('Does not render the current included usage section for enterprise members', async () => {
    const routePayload = getOverviewRoutePayloadWithAdminRole(MEMBER)
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    await waitFor(() => expect(screen.queryByTestId('total-discount')).not.toBeInTheDocument())
  })

  it('shows DiscountUsageCard for Stafftools user on enterprise route', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider
        value={{isStafftoolsRoute: true, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
      >
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('total-discount')).toBeInTheDocument()
  })
})
