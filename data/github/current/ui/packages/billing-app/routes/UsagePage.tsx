import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useSearchParams} from '@github-ui/use-navigate'
import {Box, Heading, Link} from '@primer/react'
import first from 'lodash-es/first'
import {useState, Suspense, lazy, useEffect, useContext} from 'react'

import {PageContext} from '../App'
import {Layout} from '../components'
import BudgetBanner from '../components/budget/BudgetBanner'
import {reverse} from '../utils/array'
import {UsageFilters, UsageTable, UsageChartSkeleton, GetUsageReportDialog} from '../components/usage'
import {DEFAULT_GROUP_TYPE, GROUP_BY_ORG_TYPE, GROUP_BY_REPO_TYPE} from '../constants'
import {UsagePeriod} from '../enums'

import type {BudgetAlertDetails} from '../types/budgets'
import type {Customer} from '../types/common'
import type {CustomerSelection, Filters, GroupSelection, PeriodSelection, UsageReportSelection} from '../types/usage'
import useUsageChartData from '../hooks/usage/use-usage-chart-data'
import {pageHeadingStyle} from '../utils'
import {updateUrl} from '@github-ui/history'
import type {EnabledProduct} from '../types/products'

const UsageChart = lazy(() => import('../components/usage/UsageChart'))

export interface UsagePagePayload {
  customer: Customer
  customer_selections: CustomerSelection[]
  period_selections: PeriodSelection[]
  group_selections: GroupSelection[]
  budget_alert_details: BudgetAlertDetails[]
  usage_report_selections: UsageReportSelection[]
  enabled_products: EnabledProduct[]
  current_user_email?: string
  vnext_migration_date: string
  disable_usage_reports: boolean
  use_usage_table_paginated_endpoint: boolean
  is_multi_tenant: boolean
  is_single_tenant: boolean
  min_custom_date: string
  copilot_premium_usage_report_enabled?: boolean
  billing_coding_agent_enabled?: boolean
  billing_spark_enabled?: boolean
}

export function UsagePage() {
  const payload = useRoutePayload<UsagePagePayload>()
  const {
    customer,
    customer_selections,
    group_selections: groupSelections,
    period_selections: periodSelections,
    budget_alert_details: budgetAlertDetails,
    usage_report_selections: usageReportSelections,
    current_user_email: currentUserEmail,
    enabled_products: enabledProducts,
    vnext_migration_date: vnextMigrationDate,
    disable_usage_reports: disableUsageReports,
    is_multi_tenant: isMultiTenant,
    is_single_tenant: isSingleTenant,
    min_custom_date: minCustomDate,
    copilot_premium_usage_report_enabled: copilotPremiumUsageReportEnabled = false,
    billing_coding_agent_enabled: codingAgentEnabled = false,
    billing_spark_enabled: sparkEnabled = false,
  } = payload

  // The default selected customer is the last customer in the customerSelections array.
  // The reverse method is used to reverse the order of the array so that the default selected customer
  // is shown as the first item in the customer selection dropdown.
  const customerSelections = reverse(customer_selections)
  const [searchParams] = useSearchParams()

  const setUsageFilters = () => {
    const inputGroup = searchParams.get('group')
    const inputPeriod = searchParams.get('period')
    const inputQuery = searchParams.get('query')
    const inputCustomer = searchParams.get('customer')

    return {
      customer: inputCustomer
        ? (customerSelections.find((obj: CustomerSelection) => obj.id === inputCustomer) as CustomerSelection) ??
          (first(customerSelections) as CustomerSelection)
        : (first(customerSelections) as CustomerSelection),
      group: groupSelections.find(
        (obj: GroupSelection) => obj.type === (inputGroup ? parseInt(inputGroup) : DEFAULT_GROUP_TYPE),
      ),
      period: periodSelections.find(
        (obj: PeriodSelection) => obj.type === (inputPeriod ? parseInt(inputPeriod) : UsagePeriod.DEFAULT),
      ),
      product: undefined,
      searchQuery: inputQuery ?? '',
    }
  }

  const isEnterpriseRoute = useContext(PageContext).isEnterpriseRoute
  const [filters, setFilters] = useState<Filters>(setUsageFilters)
  const {usageChartData, requestState: requestState} = useUsageChartData({filters})

  // The pricing page is disabled for multi-tenant and single-tenant environments.
  const shouldShowPricingLink = !isMultiTenant && !isSingleTenant

  const shouldShowUsageReportDialog = currentUserEmail && enabledProducts.length > 0

  useEffect(() => {
    // update the URL query parameters as the user selects a new period
    const period = filters.period?.type ?? UsagePeriod.DEFAULT
    const group = filters.group?.type ?? DEFAULT_GROUP_TYPE
    const selectedCustomer = filters.customer

    const isOrgorRepoGrouping = group === GROUP_BY_ORG_TYPE || group === GROUP_BY_REPO_TYPE
    // pagination is currently only used for org and repo groupings so only adding page param for those groupings
    const pageParam = isOrgorRepoGrouping && searchParams.get('page') ? `&page=${searchParams.get('page')}` : ''

    if (filters.searchQuery) {
      updateUrl(
        `?period=${period}&group=${group}&customer=${selectedCustomer.id}&query=${filters.searchQuery}${pageParam}`,
      )
    } else {
      updateUrl(`?period=${period}&group=${group}&customer=${selectedCustomer.id}${pageParam}`)
    }
  }, [filters, searchParams])

  return (
    <Layout>
      {budgetAlertDetails.length > 0 &&
        budgetAlertDetails.map(budgetAlertDetail => (
          <BudgetBanner key={budgetAlertDetail.budget_id} budgetAlertDetail={budgetAlertDetail} />
        ))}

      <GetUsageReportDialog>
        <GetUsageReportDialog.Notifications />

        <header className="Subhead">
          <Box sx={{display: 'flex', justifyContent: 'space-between', width: '100%', flexDirection: ['column', 'row']}}>
            <div>
              <Box sx={{mb: 2.5}}>
                <Heading as="h1" data-testid="select-cost-center" sx={pageHeadingStyle}>
                  Metered usage
                </Heading>
              </Box>

              {isEnterpriseRoute && (
                <span className="Subhead-description">
                  Includes amounts spent for organizations and repositories across all services.{' '}
                  {shouldShowPricingLink && (
                    <>
                      <Link inline href="/pricing">
                        View current and past pricing information
                      </Link>
                      .
                    </>
                  )}
                </span>
              )}
            </div>

            {shouldShowUsageReportDialog && (
              <GetUsageReportDialog.Trigger
                currentUserEmail={currentUserEmail}
                usageReportSelections={usageReportSelections}
                disableUsageReports={disableUsageReports}
                vnextMigrationDate={vnextMigrationDate}
                minCustomDate={minCustomDate}
                copilotPremiumReportEnabled={copilotPremiumUsageReportEnabled}
                codingAgentEnabled={codingAgentEnabled}
                sparkEnabled={sparkEnabled}
              />
            )}
          </Box>
        </header>
      </GetUsageReportDialog>
      <div>
        <UsageFilters
          customer={customer}
          filters={filters}
          setFilters={setFilters}
          groupSelections={groupSelections}
          periodSelections={periodSelections}
          showSearch
          enabledProducts={enabledProducts}
        />
        <Suspense fallback={<UsageChartSkeleton />}>
          <UsageChart requestState={requestState} usage={usageChartData} filters={filters} />
        </Suspense>
        <UsageTable
          filters={filters}
          isEnterpriseRoute={isEnterpriseRoute}
          codingAgentEnabled={codingAgentEnabled}
          sparkEnabled={sparkEnabled}
        />
      </div>
    </Layout>
  )
}
