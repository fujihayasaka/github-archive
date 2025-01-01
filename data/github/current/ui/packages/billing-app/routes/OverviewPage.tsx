import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Heading, LinkButton, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {InfoIcon} from '@primer/octicons-react'
import first from 'lodash-es/first'
import {useState, useContext, Suspense, lazy} from 'react'
import {reverse} from '../utils/array'
import {Fonts} from '../utils/style'
import {PageContext} from '../App'
import useBudgetsPage from '../hooks/budget/use-budgets-page'
import useRoute from '../hooks/use-route'
import {Layout, WelcomeBanner} from '../components'
import {BudgetsTable, BudgetBanner} from '../components/budget'
import {
  UsageChartSkeleton,
  CurrentPlanCard,
  DiscountUsageCard,
  TotalUsageCard,
  UsageFilters,
  ProductUsageContainer,
  OrgRepoUsageContainer,
} from '../components/usage'
import {VolumeLicensesCard} from '../components/licensing'
import {BILLING_MANAGER, ENTERPRISE_ORG_OWNER, OWNER} from '../constants'
import {UsagePeriod} from '../enums'
import {BUDGETS_ROUTE} from '../routes'
import {pageHeadingStyle} from '../utils'
import PaymentDueCard from '../components/payment_due/PaymentDueCard'
import NextPaymentCard, {type NextPaymentCardProps} from '../components/payment_due/NextPaymentCard'

import type {BudgetAlertDetails} from '../types/budgets'
import type {AdminRole, Customer} from '../types/common'
import type {EnabledProduct} from '../types/products'
import type {CustomerSelection, Filters, PeriodSelection} from '../types/usage'
import type {PaymentDueCardProps} from '../components/payment_due/PaymentDueCard'
import type {VolumeLicensesCardProps} from '../components/licensing/VolumeLicensesCard'
import {isOnTrial} from '../utils/business'
import LatestInvoiceCard from '../components/invoices/LatestInvoiceCard'
import type {LatestInvoiceCardProps} from '../components/invoices/LatestInvoiceCard'
import type {PrepaidCreditsCardProps} from '../components/prepaid_credits/PrepaidCreditsCard'
import PrepaidCreditsCard from '../components/prepaid_credits/PrepaidCreditsCard'
import useUsageChartData from '../hooks/usage/use-usage-chart-data'
import {currentUserHasBudgetWritePermissions} from '../utils/permissions'

const UsageChart = lazy(() => import('../components/usage/UsageChart'))

const overviewCardsStyle = {
  display: 'grid',
  gridTemplateColumns: ['1', '1', '1', '1', 'repeat(2, 1fr)'],
  gridGap: 3,
  mb: 3,
}

export interface OverviewPagePayload {
  admin_roles: AdminRole[]
  budget_alert_details: BudgetAlertDetails[]
  customer: Customer
  customer_selections: CustomerSelection[]
  enabled_products: EnabledProduct[]
  period_selections: PeriodSelection[]
  multi_tenant: boolean
  nextPaymentTileData: NextPaymentCardProps
  showPaymentDueTile: boolean
  paymentDueTileData: PaymentDueCardProps
  showLatestInvoiceTile: boolean
  latestInvoiceTileData: LatestInvoiceCardProps
  showVolumeLicenseSpendTile: boolean
  volumeLicenseSpendTileData: VolumeLicensesCardProps
  showPrepaidCredits: boolean
  prepaidCreditsTileData?: PrepaidCreditsCardProps
  taxDisclaimer: string
  isCopilotStandalone: boolean
  change_duration_path?: string
}

export function OverviewPage() {
  const isStafftoolsRoute = useContext(PageContext).isStafftoolsRoute
  const isEnterpriseRoute = useContext(PageContext).isEnterpriseRoute
  const isOrganizationRoute = useContext(PageContext).isOrganizationRoute
  const isUserRoute = useContext(PageContext).isUserRoute
  const isNonEnterpriseRoute = !isEnterpriseRoute && !isStafftoolsRoute

  const payload = useRoutePayload<OverviewPagePayload>()
  const {
    admin_roles: adminRoles,
    budget_alert_details: budgetAlertDetails,
    customer,
    customer_selections,
    enabled_products: enabledProducts,
    period_selections: periodSelections,
    multi_tenant: multiTenant,
    showPaymentDueTile,
    paymentDueTileData,
    nextPaymentTileData,
    showLatestInvoiceTile: showLatestInvoiceTile,
    latestInvoiceTileData,
    showVolumeLicenseSpendTile,
    volumeLicenseSpendTileData,
    showPrepaidCredits,
    prepaidCreditsTileData,
    taxDisclaimer,
    isCopilotStandalone,
    change_duration_path: changeDurationPath,
  } = payload
  // The default selected customer is the last customer in the customerSelections array.
  // The reverse method is used to reverse the order of the array so that the default selected customer
  // is shown as the first item in the customer selection dropdown.
  const customerSelections = reverse(customer_selections)
  const [filters, setFilters] = useState<Filters>(() => ({
    customer: first(customerSelections) as CustomerSelection,
    group: undefined,
    period: periodSelections.find((obj: PeriodSelection) => obj.type === UsagePeriod.DEFAULT),
    product: undefined,
    searchQuery: '',
  }))
  const {usageChartData, requestState: requestState} = useUsageChartData({filters})

  // Un-commenting this line will tell the budgets table to pull from cost center customers when selected,
  // but right now all cost centers are scoped under the enterprise. Leaving in place per @mattkorwel
  // const {budgets, deleteBudgetFromPage} = useBudgetsPage({slug, customerId: filters.customer.id})
  const {budgets, deleteBudgetFromPage} = useBudgetsPage()

  const {path: budgetsPath} = useRoute(BUDGETS_ROUTE)

  const trialCustomer = isOnTrial(customer.plan)
  const hasBudgetWritePermissions = currentUserHasBudgetWritePermissions(
    adminRoles,
    isEnterpriseRoute,
    isStafftoolsRoute,
    trialCustomer,
  )
  // TODO: Filter based on the product
  const hasAccessToAllUsage = adminRoles.includes(OWNER) || adminRoles.includes(BILLING_MANAGER)
  const isOnlyOrgAdmin = !hasAccessToAllUsage && adminRoles.includes(ENTERPRISE_ORG_OWNER)
  const canViewDiscountUsage =
    adminRoles.includes(OWNER) || adminRoles.includes(BILLING_MANAGER) || isOrganizationRoute || isOnlyOrgAdmin

  return (
    <Layout data-hpc>
      {!isStafftoolsRoute && !customer.isVNextNative && (
        <WelcomeBanner multiTenant={multiTenant} isEnterprise={isEnterpriseRoute} />
      )}
      {budgetAlertDetails.length > 0 &&
        budgetAlertDetails.map(budgetAlertDetail => (
          <BudgetBanner key={budgetAlertDetail.budget_id} budgetAlertDetail={budgetAlertDetail} />
        ))}
      <header className="Subhead">
        <Heading as="h2" className="Subhead-heading h1-override-shared-component" sx={pageHeadingStyle}>
          Overview
        </Heading>
      </header>

      <Box
        sx={{
          ...overviewCardsStyle,
          gridTemplateColumns:
            showPaymentDueTile || showLatestInvoiceTile || isNonEnterpriseRoute
              ? ['1', '1', '1', '1', 'repeat(3, 1fr)']
              : overviewCardsStyle.gridTemplateColumns,
        }}
      >
        <TotalUsageCard customerSelections={customerSelections} isOrgAdmin={isOnlyOrgAdmin} />
        {canViewDiscountUsage && (
          <DiscountUsageCard
            enabledProducts={enabledProducts}
            isOrganization={isOrganizationRoute}
            isUser={isUserRoute}
            isEnterpriseOrgOwner={isOnlyOrgAdmin}
          />
        )}
        {showPaymentDueTile && <PaymentDueCard {...paymentDueTileData} />}
        {showLatestInvoiceTile && <LatestInvoiceCard {...latestInvoiceTileData} />}
        {isNonEnterpriseRoute && <NextPaymentCard {...nextPaymentTileData} />}
      </Box>
      {!isEnterpriseRoute && (
        <Box sx={{mb: 3}}>
          <CurrentPlanCard customer={customer} changeDurationPath={changeDurationPath} />
        </Box>
      )}
      {taxDisclaimer && (
        <Box sx={{mb: 4, mt: -2}}>
          <Box sx={{display: 'flex'}} data-testid="sales-tax-disclaimer-fineprint">
            <Octicon sx={{color: 'fg.muted', pr: 1}} icon={InfoIcon} size={16} />
            <Text as="p" sx={{color: 'fg.muted', fontSize: Fonts.FontSizeSmall}}>
              {taxDisclaimer}
            </Text>
          </Box>
        </Box>
      )}

      {showVolumeLicenseSpendTile && (
        <Box sx={{mb: 4}}>
          <VolumeLicensesCard {...volumeLicenseSpendTileData} />
        </Box>
      )}
      {showPrepaidCredits && <PrepaidCreditsCard {...prepaidCreditsTileData} />}
      <Box sx={{mb: 3}}>
        <Heading as="h2" data-testid="select-cost-center" sx={pageHeadingStyle}>
          Metered usage
        </Heading>
      </Box>

      <Box sx={{mb: 3}}>
        <Suspense fallback={<UsageChartSkeleton />}>
          <UsageChart requestState={requestState} usage={usageChartData} filters={filters} showTitle={false}>
            <UsageFilters
              customer={customer}
              filters={filters}
              setFilters={setFilters}
              periodSelections={periodSelections}
              showSearch={false}
              sx={{mb: 0}}
            />
          </UsageChart>
        </Suspense>
      </Box>

      <OrgRepoUsageContainer filters={filters} />

      <ProductUsageContainer
        customer={customer}
        enabledProducts={enabledProducts}
        filters={filters}
        isCopilotStandalone={isCopilotStandalone}
        isOnlyOrgAdmin={isOnlyOrgAdmin}
      />

      {/* // Trial customers cannot create budgets */}
      {!trialCustomer && isEnterpriseRoute && (
        <div>
          <Box sx={{display: 'flex', alignItems: 'center', mb: 3}}>
            <Heading as="h2" sx={{fontSize: 3}} data-testid="budgets-section">
              Budgets
            </Heading>
            {hasBudgetWritePermissions && (
              <LinkButton
                href={budgetsPath}
                sx={{color: 'btn.text', ml: 'auto', ':hover': {textDecoration: 'none'}}}
                underline={false}
              >
                Manage budgets
              </LinkButton>
            )}
          </Box>
          <BudgetsTable
            budgets={budgets}
            hasBudgetWritePermissions={hasBudgetWritePermissions}
            deleteBudget={deleteBudgetFromPage}
            enabledProducts={enabledProducts}
          />
        </div>
      )}
    </Layout>
  )
}
