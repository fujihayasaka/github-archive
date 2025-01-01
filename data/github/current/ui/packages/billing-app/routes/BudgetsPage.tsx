import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Heading, LinkButton, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Blankslate} from '@primer/react/experimental'

import BudgetsTable from '../components/budget/BudgetsTable'
import Layout from '../components/Layout'
import {BUDGET_SCOPE_CUSTOMER, BUDGET_SCOPE_ENTERPRISE} from '../constants'
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

export interface BudgetsPagePayload {
  customer: Customer
  type: string
  budgets: Budget[]
  adminRoles: AdminRole[]
  enabledProducts: Product[]
  helpUrl: string
}

export function BudgetsPage() {
  const payload = useRoutePayload<BudgetsPagePayload>()
  const {adminRoles, customer, enabledProducts, helpUrl} = payload

  const {budgets, deleteBudgetFromPage, requestState} = useBudgetsPage()
  const isOrganizationRoute = useContext(PageContext).isOrganizationRoute
  const isEnterpriseRoute = useContext(PageContext).isEnterpriseRoute

  let customerBudgets
  let nonCustomerBudgets
  if (isOrganizationRoute) {
    customerBudgets = budgets
      .filter(b => b.targetType === BUDGET_SCOPE_CUSTOMER) // TODO: remove 'Enterprise' after data migration
      .sort((a, b) => {
        return a.targetName > b.targetName ? 1 : -1
      })
    nonCustomerBudgets = budgets
      .filter(b => b.targetType !== BUDGET_SCOPE_ENTERPRISE && b.targetType !== BUDGET_SCOPE_CUSTOMER) // TODO: remove 'Enterprise' after data migration
      .sort((a, b) => {
        return a.targetName > b.targetName ? 1 : -1
      })
  } else {
    customerBudgets = budgets
      .filter(b => b.targetType === BUDGET_SCOPE_CUSTOMER || b.targetType === BUDGET_SCOPE_ENTERPRISE) // TODO: remove 'Enterprise' after data migration
      .sort((a, b) => {
        return a.targetName > b.targetName ? 1 : -1
      })
    nonCustomerBudgets = budgets
      .filter(b => b.targetType !== BUDGET_SCOPE_CUSTOMER && b.targetType !== BUDGET_SCOPE_ENTERPRISE) // TODO: remove 'Enterprise' after data migration
      .sort((a, b) => {
        return a.targetName > b.targetName ? 1 : -1
      })
  }

  const isStafftoolsRoute = useContext(PageContext).isStafftoolsRoute
  const trialCustomer = isOnTrial(customer.plan)
  const hasBudgetWritePermissions = currentUserHasBudgetWritePermissions(
    adminRoles,
    isEnterpriseRoute,
    isStafftoolsRoute,
    trialCustomer,
  )
  const budgetsDocsUrl = `${helpUrl}/early-access/billing/billing-private-beta#using-budgets-and-alerts`
  const budgetsLength = customerBudgets.length + nonCustomerBudgets.length
  const customerTableLabel = isOrganizationRoute ? 'Organization' : 'Enterprise'

  const {path: newBudgetPath} = useRoute(NEW_BUDGET_ROUTE)
  return (
    <Layout>
      <header className="Subhead">
        <Heading as="h2" className="Subhead-heading" sx={pageHeadingStyle}>
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
                <Heading as="h3" sx={{mb: 1, fontSize: Fonts.SectionHeadingFontSize}}>
                  No budgets created
                </Heading>
                <Text as="p" sx={{mb: Spacing.CardMargin, color: 'fg.muted', textAlign: 'center'}}>
                  Create budgets to track your spending on products like Actions and Copilot for a single repository or
                  the entire organization.
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
                      isCustomerTable
                      customerTableLabel={customerTableLabel}
                      isEnterpriseRoute={isEnterpriseRoute}
                      hasBudgetWritePermissions={hasBudgetWritePermissions}
                    />
                  </div>
                  <br />
                  <div>
                    <BudgetsTable
                      budgets={nonCustomerBudgets}
                      deleteBudget={deleteBudgetFromPage}
                      enabledProducts={enabledProducts}
                      isEnterpriseRoute={isEnterpriseRoute}
                      hasBudgetWritePermissions={hasBudgetWritePermissions}
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
