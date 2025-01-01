import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor} from '@testing-library/react'
import {OverviewPage} from '../../routes/'
import {
  getOverviewRoutePayload,
  getOverviewRoutePayloadWithEmptyAlert,
  getOverviewRoutePayloadWithMultipleAlerts,
  getUsageRoutePayloadWithPrepaidCredits,
} from '../../test-utils/mock-data'
import {PageContext} from '../../App'

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

describe('Overview page', () => {
  it('Renders the Overview page', async () => {
    const date = new Date()
    const month = date.toLocaleDateString('en-US', {timeZone: 'UTC', month: 'short'})
    const firstDay = new Date(date.getFullYear(), date.getMonth(), 1).getDate()
    const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()

    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false}}>
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )

    // use find by and await for this since getAllByRole fails with suspense loaded component
    expect(await screen.findByTestId('usage-chart-subtitle')).toHaveTextContent(
      `${month} ${firstDay} - ${month} ${lastDay}, ${date.getFullYear()}`,
    )

    const headings = await screen.findAllByRole('heading')

    expect(headings[0]).toHaveTextContent('Overview')
    expect(headings[1]).toHaveTextContent('Current metered usage')
    expect(headings[2]).toHaveTextContent('Metered usage')
    expect(headings[4]).toHaveTextContent('Usage by organization')
    expect(headings[5]).toHaveTextContent('Usage by repository')
    expect(headings[6]).toHaveTextContent('Products selector navigation')
    expect(headings[7]).toHaveTextContent('Actions usage')
    expect(headings[8]).toHaveTextContent('Budgets')
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

  it('Shows the budgets section for a non-trial customer', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false}}>
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    await act(async () => {
      expect(await screen.findByTestId('budgets-section')).toBeInTheDocument()
    })
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
      <PageContext.Provider value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false}}>
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('org-usage-card')).toBeInTheDocument()
  })

  it('Hides the "Usage by organization" tile on org view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: true}}>
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    await waitFor(() => expect(screen.queryByTestId('org-usage-card')).not.toBeInTheDocument())
  })

  it('Shows the "Current plan" tile on org view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: true}}>
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    expect(await screen.findByTestId('current-plan-card')).toBeInTheDocument()
  })

  it('Hides the "Current plan" tile on enterprise view', async () => {
    const routePayload = getOverviewRoutePayload()
    render(
      <PageContext.Provider value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false}}>
        <OverviewPage />
      </PageContext.Provider>,
      {routePayload},
    )
    await waitFor(() => expect(screen.queryByTestId('current-plan-card')).not.toBeInTheDocument())
  })
})
