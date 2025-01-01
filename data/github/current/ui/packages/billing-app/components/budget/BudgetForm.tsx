import {useCallback, useState, useEffect, useContext} from 'react'
import {Box, Breadcrumbs, Flash, Button, Heading, Text} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {Dialog, Octicon} from '@primer/react/deprecated'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useNavigate} from '@github-ui/use-navigate'
import {CheckCircleIcon, AlertIcon} from '@primer/octicons-react'

import {
  BILLING_MANAGER,
  ENTERPRISE_ORG_OWNER,
  BUDGET_SCOPE_COST_CENTER,
  BUDGET_SCOPE_CUSTOMER,
  BUDGET_SCOPE_ORGANIZATION,
  BUDGET_SCOPE_REPOSITORY,
  HighWatermarkProducts,
  HighWatermarkSkus,
  OWNER,
  CopilotPremiumRequestSku,
  ModelsInferenceSku,
} from '../../constants'
import {BudgetLimitTypes} from '../../enums/budgets'
import {HTTPMethod, doRequest} from '../../hooks/use-request'
import useRoute from '../../hooks/use-route'
import {
  BUDGETS_ROUTE,
  PAYMENT_INFO_ROUTE,
  UPSERT_BUDGET_ROUTE,
  MODELS_ROUTE,
  MODELS_ROUTE_ENT,
  MODELS_ROUTE_ORG,
} from '../../routes'

import {BudgetAmount} from './BudgetAmount'
import {BudgetAlertSelector} from './BudgetAlertSelector'
import {BudgetOrgAlertSelector} from './BudgetOrgAlertSelector'
import {BudgetUserAlertSelector} from './BudgetUserAlertSelector'
import {BudgetProductSelector} from './BudgetProductSelector'
import {BudgetScopeSelector} from './BudgetScopeSelector'
import {BudgetSelectedProduct} from './BudgetSelectedProduct'
import {BudgetSelectedScope} from './BudgetSelectedScope'
import {PageContext} from '../../App'

import type {UpsertBudgetRequest, EditBudget, BudgetPicker} from '../../types/budgets'
import type {AdminRole} from '../../types/common'
import type {Product} from '../../types/products'
import type {PricingDetails} from '../../types/pricings'
import styles from './BudgetForm.module.css'

type Props = {
  budget?: EditBudget
  slug: string
  currentUserId?: string
  adminRoles: AdminRole[]
  enabledProducts: Product[]
  enabledSkus: PricingDetails[]
  showMissingPaymentBanner: boolean
  showModelsBanner?: boolean
  codingAgentEnabled: boolean
  sparkEnabled: boolean
}

export const defaultBudgetLimitType = (product: string) => {
  // By default, Actions will not enforce a hard limit on usage
  // High watermark/seat based products cannot enforce a hard limit, since usage cannot be adjusted during the month
  if (isProductHighWaterMark(product) || isSkuHighWaterMark(product)) {
    return BudgetLimitTypes.AlertingOnly
  }
  return BudgetLimitTypes.PreventFurtherUsage
}

const isProductHighWaterMark = (product: string) => {
  return Object.values(HighWatermarkProducts).includes(product as HighWatermarkProducts)
}

const isSkuHighWaterMark = (sku: string) => {
  return Object.values(HighWatermarkSkus).includes(sku as HighWatermarkSkus)
}

export default function BudgetForm({
  budget,
  slug,
  currentUserId,
  adminRoles,
  enabledProducts,
  enabledSkus,
  showMissingPaymentBanner,
  showModelsBanner,
  codingAgentEnabled,
  sparkEnabled,
}: Props) {
  const [sortedEnabledProducts] = useState(() => [...enabledProducts].sort((a, b) => a.name.localeCompare(b.name)))
  const navigate = useNavigate()
  const [budgetAmount, setBudgetAmount] = useState<number | string>(budget ? budget.targetAmount : 0)
  const [budgetValue, setBudgetValue] = useState(
    budget ? budget?.pricingTargetId : sortedEnabledProducts[0]?.name || 'actions',
  )
  const [budgetType, setBudgetType] = useState(budget ? budget?.pricingTargetType : 'ProductPricing')

  const [budgetLimitType, setBudgetLimitType] = useState<BudgetLimitTypes>(() =>
    budget ? budget.budgetLimitType : defaultBudgetLimitType(budgetValue),
  )
  const [budgetScope, setBudgetScope] = useState<string>(budget ? budget.targetType : BUDGET_SCOPE_CUSTOMER)
  const [budgetScopeIds, setBudgetScopeId] = useState<string[]>(budget ? [budget.targetId] : ['1'])

  const [alertEnabled, setAlertEnabled] = useState<boolean>(budget?.alertEnabled ?? true)
  const defaultRecipient = currentUserId ? [currentUserId] : []
  const [alertRecipientUserIds, setAlertRecipientUserIds] = useState<string[]>(
    budget?.alertRecipientUserIds ? budget.alertRecipientUserIds : defaultRecipient,
  )
  const [isConfirmUpdateDialogOpen, setIsConfirmUpdateDialogOpen] = useState(false)
  const onConfirmUpdateDialogOpen = useCallback((e: React.FormEvent<EventTarget>) => {
    e.preventDefault()
    return setIsConfirmUpdateDialogOpen(true)
  }, [])
  const onConfirmUpdateDialogClose = useCallback(() => setIsConfirmUpdateDialogOpen(false), [])
  const [showSkuErrorBanner, setShowSkuErrorBanner] = useState(false)
  const [skuFilter, setSkuFilter] = useState('')

  const {isEnterpriseRoute, isOrganizationRoute, isUserRoute} = useContext(PageContext)

  useEffect(() => {
    if (!budget) {
      setBudgetLimitType(defaultBudgetLimitType(budgetValue))
    }
  }, [budgetValue, budget])

  const {addToast} = useToastContext()

  const action = budget ? 'edit' : 'create'

  const {path: allBudgetsRoute} = useRoute(BUDGETS_ROUTE)
  const {path: editBudgetsRoute} = useRoute(UPSERT_BUDGET_ROUTE, {budgetUUID: budget?.uuid ?? ''})
  const {path: paymentInfoRoute} = useRoute(PAYMENT_INFO_ROUTE)
  const {path: modelsRoute} = useRoute(
    isEnterpriseRoute ? MODELS_ROUTE_ENT : isOrganizationRoute ? MODELS_ROUTE_ORG : MODELS_ROUTE,
  )

  const modelsBillingRequired = showModelsBanner && (budgetValue === 'models' || skuFilter === 'Models')

  const mapPricingTypeToString = (pricingType: string): string => {
    switch (pricingType) {
      case 'SkuPricing':
        return 'SKU'
      case 'ProductPricing':
        return 'Product'
      default:
        return 'Product'
    }
  }

  async function createBudget() {
    const data: UpsertBudgetRequest = {
      targetAmount: budgetAmount as number,
      targetType: budgetScope,
      targetId: budgetScopeIds[0] ?? '1', // We only support single scope creation right now
      pricingTargetType: budgetType,
      pricingTargetId: budgetValue,
      budgetLimitType,
      alertEnabled,
      alertRecipientUserIds: alertEnabled ? alertRecipientUserIds : [],
    }

    try {
      const res = await doRequest<UpsertBudgetRequest>(HTTPMethod.POST, allBudgetsRoute, data)
      if (!res.ok) {
        let message = 'There was an issue creating your budget'

        if (res.data?.error?.includes('Budget with this key already exists')) {
          message = `A budget for this product and scope already exists. Please edit the existing budget instead of creating another.`
        } else if (res.data?.error?.includes('Payment method is missing')) {
          message = 'Please add a payment method to use budgets.'
        }

        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message,
          role: 'alert',
        })
      } else {
        navigate(allBudgetsRoute)
      }
    } catch {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: 'There was an issue creating your budget',
        role: 'alert',
      })
    }
  }

  async function editBudget() {
    if (!budget) return

    const data: UpsertBudgetRequest = {
      targetAmount: budgetAmount as number,
      targetType: budgetScope,
      targetId: budgetScopeIds[0] ?? '1', // We only support single scope creation right now
      pricingTargetType: budget.pricingTargetType,
      pricingTargetId: budget.pricingTargetId,
      budgetLimitType,
      alertEnabled,
      alertRecipientUserIds: alertEnabled ? alertRecipientUserIds : [],
    }

    try {
      const res = await doRequest<UpsertBudgetRequest>(HTTPMethod.PUT, editBudgetsRoute, data)
      if (!res.ok) {
        let message = 'There was an issue editing your budget'
        if (res.data?.error?.includes('Payment method is missing')) {
          message = 'Please add a payment method to use budgets.'
        }
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message,
          role: 'alert',
        })
      } else {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'success',
          message: `Your budget has been updated`,
          icon: <CheckCircleIcon />,
          role: 'status',
        })
        navigate(allBudgetsRoute)
      }
    } catch {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: 'There was an issue editing your budget',
        role: 'alert',
      })
    }
  }

  const handleSubmit = async (e?: React.FormEvent<EventTarget>) => {
    e?.preventDefault()
    if (!budgetScopeIds[0]) {
      let message = ''
      switch (budgetScope) {
        case BUDGET_SCOPE_ORGANIZATION:
          message = 'Please select at least one organization in order to successfully create a budget'
          break
        case BUDGET_SCOPE_REPOSITORY:
          message = 'Please select at least one repository in order to successfully create a budget'
          break
        case BUDGET_SCOPE_COST_CENTER:
          message = 'Please select at least one cost center in order to successfully create a budget'
          break
        default:
          message = 'Please select a scope in order to successfully create a budget'
      }
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message,
        role: 'alert',
      })
      return
    }

    if (alertEnabled && alertRecipientUserIds.length === 0) {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: 'At least one alert recipient must be selected',
        role: 'alert',
      })
      return
    }

    if (!budgetValue) {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: `A ${mapPricingTypeToString(budgetType)} must be selected`,
        role: 'alert',
      })
      return
    }

    const isValidSku = enabledSkus.some(sku => sku.sku === budgetValue)
    if (budgetType === 'SkuPricing' && !isValidSku) {
      setShowSkuErrorBanner(true)
      return
    }

    setIsConfirmUpdateDialogOpen(false)
    if (action === 'edit') {
      await editBudget()
    } else {
      await createBudget()
    }
  }

  const calculateDisablePicker = useCallback(() => {
    const disablePicker: BudgetPicker[] = []

    if (isEnterpriseRoute) {
      if (
        !adminRoles.includes(ENTERPRISE_ORG_OWNER) &&
        (adminRoles.includes(OWNER) || adminRoles.includes(BILLING_MANAGER))
      ) {
        disablePicker.push('repo')
      }

      if (
        adminRoles.includes(ENTERPRISE_ORG_OWNER) &&
        !(adminRoles.includes(OWNER) || adminRoles.includes(BILLING_MANAGER))
      ) {
        disablePicker.push('org', 'enterprise')
      }
    } else if (isOrganizationRoute) {
      disablePicker.push('enterprise', 'cost_center')
    } else {
      disablePicker.push('org', 'cost_center', 'enterprise')
    }

    if (budgetValue === 'models' || budgetValue === ModelsInferenceSku) {
      disablePicker?.push('repo')
    }

    if (budgetValue === CopilotPremiumRequestSku) {
      disablePicker?.push('repo')
      if (!isOrganizationRoute) {
        disablePicker?.push('org')
      }
    }

    return disablePicker
  }, [isEnterpriseRoute, isOrganizationRoute, adminRoles, budgetValue])

  const [disablePicker, setDisablePicker] = useState(() => calculateDisablePicker())

  useEffect(() => {
    setDisablePicker(calculateDisablePicker())
  }, [adminRoles, isEnterpriseRoute, isOrganizationRoute, isUserRoute, budgetValue, calculateDisablePicker])

  const shouldConfirmEditModalBeDisplayed = () => {
    if (
      budget &&
      (budgetAmount as number) < budget.targetAmount &&
      budgetLimitType === BudgetLimitTypes.PreventFurtherUsage &&
      action === 'edit'
    ) {
      return true
    }
    return false
  }

  return (
    <>
      {budgetType === 'SkuPricing' && showSkuErrorBanner && (
        <Banner
          data-testid="budget-error-banner"
          title="budget-error-banner"
          hideTitle
          className={styles.BudgetErrorBanner}
          variant="critical"
        >
          <span>Please select a SKU to continue</span>
        </Banner>
      )}
      {modelsBillingRequired && (
        <Banner
          className={styles.BudgetErrorBanner}
          aria-label="Billing for Models is required"
          title="Billing for Models is required"
          description="Enable Models billing to set a budget."
          variant="critical"
          primaryAction={
            <Banner.PrimaryAction onClick={() => navigate(modelsRoute)}>Enable paid usage</Banner.PrimaryAction>
          }
        />
      )}
      <Breadcrumbs className={styles.BudgetFormBreadcrumbs}>
        <Breadcrumbs.Item href="../budgets">Budgets and Alerts</Breadcrumbs.Item>
        <Breadcrumbs.Item href="#" selected>
          New monthly budget
        </Breadcrumbs.Item>
      </Breadcrumbs>

      <header className="Subhead flex-column">
        <Heading as="h1">{action === 'edit' ? 'Edit monthly budget' : 'New monthly budget'}</Heading>
        {action === 'create' && (
          <Text sx={{color: 'fg.muted'}}>Create a budget to track spending for a selected product and scope.</Text>
        )}
      </header>
      {showMissingPaymentBanner && (
        <Banner
          variant="warning"
          title="Payment method is missing"
          description="Please set up a valid payment method before creating or adjusting your budget."
          primaryAction={
            <Banner.PrimaryAction onClick={() => navigate(paymentInfoRoute)}>Add payment method</Banner.PrimaryAction>
          }
        />
      )}
      <Box sx={{maxWidth: '65ch'}}>
        <form
          onSubmit={shouldConfirmEditModalBeDisplayed() ? onConfirmUpdateDialogOpen : handleSubmit}
          className={styles.BudgetFormWrapper}
        >
          {action === 'create' && (
            <>
              <BudgetProductSelector
                budgetType={budgetType}
                budgetValue={budgetValue}
                setBudgetType={setBudgetType}
                setBudgetValue={setBudgetValue}
                products={enabledProducts}
                skus={enabledSkus}
                isUserRoute={isUserRoute}
                showSkuError={showSkuErrorBanner}
                showModelsBillingError={modelsBillingRequired}
                skuFilter={skuFilter}
                setSkuFilter={setSkuFilter}
                codingAgentEnabled={codingAgentEnabled}
                sparkEnabled={sparkEnabled}
              />
              <BudgetScopeSelector
                budgetScope={budgetScope}
                setBudgetScope={setBudgetScope}
                setBudgetScopeId={setBudgetScopeId}
                budgetScopeIds={budgetScopeIds}
                slug={slug}
                disablePicker={disablePicker}
                budgetProduct={budgetValue}
              />
            </>
          )}
          {action === 'edit' && (
            <Box sx={{pt: 1}}>
              <BudgetSelectedProduct
                budgetValue={budgetValue}
                enabledSkus={enabledSkus}
                enabledProducts={enabledProducts}
              />
              <BudgetSelectedScope budgetScope={budgetScope} budgetTargetName={budget?.targetName || ''} />
            </Box>
          )}
          <BudgetAmount
            budgetAmount={budgetAmount}
            setBudgetAmount={setBudgetAmount}
            action={action}
            budgetLimitType={budgetLimitType}
            setBudgetLimitType={setBudgetLimitType}
            budgetProduct={budgetValue}
          />
          {isEnterpriseRoute && (
            <BudgetAlertSelector
              alertEnabled={alertEnabled}
              setAlertEnabled={setAlertEnabled}
              alertRecipientUserIds={alertRecipientUserIds}
              setAlertRecipientUserIds={setAlertRecipientUserIds}
              slug={slug}
            />
          )}
          {isOrganizationRoute && (
            <BudgetOrgAlertSelector
              alertEnabled={alertEnabled}
              setAlertEnabled={setAlertEnabled}
              alertRecipientUserIds={alertRecipientUserIds}
              setAlertRecipientUserIds={setAlertRecipientUserIds}
              orgName={slug}
            />
          )}
          {isUserRoute && (
            <BudgetUserAlertSelector
              alertEnabled={alertEnabled}
              setAlertEnabled={setAlertEnabled}
              setAlertRecipientUserIds={setAlertRecipientUserIds}
              defaultRecipient={defaultRecipient}
            />
          )}
          <Box as="hr" sx={{p: 1}} />
          <Box sx={{display: 'flex'}}>
            <Button type="submit" variant="primary" disabled={modelsBillingRequired}>
              {action === 'edit' ? 'Update budget' : 'Create budget'}
            </Button>
            <Button sx={{ml: 2}} onClick={() => navigate(allBudgetsRoute)}>
              Cancel
            </Button>
          </Box>
        </form>
      </Box>
      {isConfirmUpdateDialogOpen && (
        <Dialog
          aria-labelledby="confirm-budget-edit-dialog-header"
          data-testid="confirm-budget-edit-dialog"
          title="Confirm budget update"
          onDismiss={onConfirmUpdateDialogClose}
          isOpen={isConfirmUpdateDialogOpen}
          sx={{width: 470}}
        >
          <Dialog.Header sx={{border: 0, bg: 'transparent'}}>Confirm editing budget</Dialog.Header>
          <Box sx={{px: 3}}>
            <Text as="p" sx={{mb: 0}}>
              Are you sure you want to save changes made to this monthly budget?
            </Text>
            <Flash variant="warning" sx={{display: 'flex', mt: 3, mb: 2}}>
              <Octicon icon={AlertIcon} size={20} sx={{mr: 2, pt: 1, color: 'accent.fg'}} />
              <span>
                Usage for the selected product may be stopped, in case the updated budget limit is less than the spend
                already incurred this month.
              </span>
            </Flash>
          </Box>
          <Box sx={{display: 'flex', justifyContent: 'flex-end', p: 3}}>
            <Button onClick={onConfirmUpdateDialogClose} sx={{mr: 2}}>
              Cancel
            </Button>
            <Button onClick={handleSubmit} variant="danger" data-testid="confirm-budget-edit-dialog-cancel">
              Confirm
            </Button>
          </Box>
        </Dialog>
      )}
    </>
  )
}
