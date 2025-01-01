import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Heading, LinkButton, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Blankslate} from '@primer/react/experimental'

import BudgetsTable from '../components/budget/BudgetsTable'
import Layout from '../components/Layout'
import useBudgetsPage from '../hooks/budget/use-budgets-page'
import useRoute from '../hooks/use-route'
import {NEW_BUDGET_ROUTE} from '../routes'
import {Fonts, Spacing, boxStyle, pageHeadingStyle} from '../utils'
import {useContext} from 'react'
import {isOnTrial} from '../utils/business'

import {PageContext} from '../App'
import type {Budget} from '../types/budgets'
import type {AdminRole, Customer} from '../types/common'
import type {Product} from '../types/products'
import {GoalIcon, InfoIcon, MeterIcon} from '@primer/octicons-react'
import {RequestState} from '../enums'
import {currentUserHasBudgetWritePermissions} from '../utils/permissions'
import useFilteredBudgets from '../hooks/budget/use-filtered-budgets'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import type {PricingDetails} from '../types/pricings'
import {CopilotPremiumRequestSku} from '../constants'

export interface BudgetsPagePayload {
  customer: Customer
  type: string
  budgets: Budget[]
  adminRoles: AdminRole[]
  enabledProducts: Product[]
  enabledSkus: PricingDetails[]
  helpUrl: string
  copilotIapSubscription: boolean
}

const customerTableLabelText = (
  isOrganizationRoute: boolean,
  isUserRoute: boolean,
  isStafftoolsRoute: boolean,
  isEnterpriseRoute: boolean,
) => {
  if (isUserRoute || (isStafftoolsRoute && !isEnterpriseRoute)) {
    // Calling these `Account` budgets for both orgs/users in stafftools
    return 'Account'
  } else if (isOrganizationRoute) {
    return 'Organization'
  } else {
    return 'Enterprise'
  }
}

export function BudgetsPage() {
  const payload = useRoutePayload<BudgetsPagePayload>()
  const {adminRoles, customer, enabledProducts, enabledSkus, helpUrl, copilotIapSubscription} = payload

  const {budgets, deleteBudgetFromPage, requestState} = useBudgetsPage()
  const {isOrganizationRoute, isEnterpriseRoute, isUserRoute, isStafftoolsRoute} = useContext(PageContext)
  const {customerBudgets, nonCustomerBudgets} = useFilteredBudgets(budgets, isOrganizationRoute, isUserRoute)

  const copilotPremiumSKUEnabled = isFeatureEnabled('billingplatform_copilot_premium_sku')

  const trialCustomer = isOnTrial(customer.plan)
  const hasBudgetWritePermissions = currentUserHasBudgetWritePermissions(
    adminRoles,
    isEnterpriseRoute,
    isStafftoolsRoute,
    trialCustomer,
  )
  const budgetsDocsUrl = `${helpUrl}/early-access/billing/billing-private-beta#using-budgets-and-alerts`
  const premiumRequestsBudgets = copilotPremiumSKUEnabled
    ? 0
    : [...customerBudgets, ...nonCustomerBudgets].filter(budget => budget.pricingTargetId === CopilotPremiumRequestSku)
        .length

  const budgetsLength = Math.max(0, customerBudgets.length + nonCustomerBudgets.length - premiumRequestsBudgets)
  const customerTableLabel = customerTableLabelText(
    isOrganizationRoute,
    isUserRoute,
    isStafftoolsRoute,
    isEnterpriseRoute,
  )

  const {path: newBudgetPath} = useRoute(NEW_BUDGET_ROUTE)

  const getInitialBudgetsText = () => {
    const baseText = 'Create budgets to track your spending on products like Actions and Copilot'
    return isUserRoute ? `${baseText}.` : `${baseText} for a single repository or the entire organization.`
  }

  return (
    <Layout>
      <header className="Subhead">
        <Heading as="h1" className="Subhead-heading" sx={pageHeadingStyle}>
          Budgets and alerts
        </Heading>
        {hasBudgetWritePermissions && (
          <LinkButton
            href={newBudgetPath}
            sx={{color: 'btn.text', ':hover': {textDecoration: 'none'}}}
            underline={false}
          >
            <Text sx={{fontWeight: 'normal'}}>New budget</Text>
          </LinkButton>
        )}
      </header>
      {trialCustomer ? (
        <div className="text-center">
          <Blankslate border>
            <Blankslate.Visual>
              <GoalIcon size={24} />
            </Blankslate.Visual>
            <Blankslate.Heading>Track spending using budgets</Blankslate.Heading>
            <Blankslate.Description>
              <span>
                You can create budgets to track your spending on products like Actions and Copilot for an organization,
                repository, cost center or the entire enterprise.
              </span>
              <br />
              <br />
              <span>
                <InfoIcon size={16} /> This is a paid feature and is not included as part of your trial.
              </span>
            </Blankslate.Description>
            <Blankslate.SecondaryAction href={budgetsDocsUrl}>Learn more about budgets</Blankslate.SecondaryAction>
          </Blankslate>
        </div>
      ) : (
        <>
          {budgetsLength === 0 && !isStafftoolsRoute && requestState === RequestState.IDLE ? (
            <Box
              sx={{
                ...boxStyle,
                padding: Spacing.StandardPadding * 2,
                display: 'flex',
                flexDirection: 'column',
                justifyContent: 'center',
                alignItems: 'center',
              }}
            >
              <Box sx={{mb: Spacing.StandardPadding}}>
                <Octicon icon={MeterIcon} size={24} />
              </Box>
              <Box
                sx={{
                  width: 600,
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'center',
                  alignItems: 'center',
                }}
              >
                <Heading as="h1" sx={{mb: 1, fontSize: Fonts.SectionHeadingFontSize}}>
                  No budgets created
                </Heading>
                <Text as="p" sx={{mb: Spacing.CardMargin, color: 'fg.muted', textAlign: 'center'}}>
                  {getInitialBudgetsText()}
                </Text>
              </Box>
              {hasBudgetWritePermissions && (
                <LinkButton href={newBudgetPath} variant="primary">
                  New Budget
                </LinkButton>
              )}
            </Box>
          ) : (
            <>
              {requestState === RequestState.IDLE && (
                <>
                  <div>
                    <BudgetsTable
                      budgets={customerBudgets}
                      deleteBudget={deleteBudgetFromPage}
                      enabledProducts={enabledProducts}
                      enabledSkus={enabledSkus}
                      isCustomerTable
                      customerTableLabel={customerTableLabel}
                      isEnterpriseRoute={isEnterpriseRoute}
                      hasBudgetWritePermissions={hasBudgetWritePermissions}
                      copilotIapSubscription={copilotIapSubscription}
                    />
                  </div>
                  <br />
                  <div>
                    <BudgetsTable
                      budgets={nonCustomerBudgets}
                      deleteBudget={deleteBudgetFromPage}
                      enabledProducts={enabledProducts}
                      enabledSkus={enabledSkus}
                      isEnterpriseRoute={isEnterpriseRoute}
                      hasBudgetWritePermissions={hasBudgetWritePermissions}
                      copilotIapSubscription={copilotIapSubscription}
                    />
                  </div>
                </>
              )}
            </>
          )}
        </>
      )}
    </Layout>
  )
}
