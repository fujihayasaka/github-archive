import {useContext, useState} from 'react'
import {Box, Link, Text} from '@primer/react'
import {InlineMessage} from '@primer/react/experimental'
import {useNavigate} from 'react-router-dom'
import {OrganizationIcon, RepoIcon, GlobeIcon, CreditCardIcon} from '@primer/octicons-react'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {BudgetLabel, BudgetProgressBar, BudgetWarningIcon, BudgetActionMenu} from '.'
import {ResourceType} from '../../enums/cost-centers'
import {formatMoneyDisplay} from '../../utils/money'
import {tableRowStyle} from '../../utils/style'
import {tableDataCellStyle, tableRowStyleRowtoCol} from './style'
import {BudgetPricingTargetType, type Budget} from '../../types/budgets'
import {
  BUDGET_SCOPE_ORGANIZATION,
  BUDGET_SCOPE_ENTERPRISE,
  BUDGET_SCOPE_CUSTOMER,
  BUDGET_SCOPE_REPOSITORY,
  CopilotPremiumRequestSku,
} from '../../constants'
import useRoute from '../../hooks/use-route'
import {EDIT_BUDGET_ROUTE, EDIT_COST_CENTER_ROUTE, UPSERT_BUDGET_ROUTE} from '../../routes'
import {doRequest, HTTPMethod} from '../../hooks/use-request'
import type {Product} from '../../types/products'
import {PageContext} from '../../App'
import type {PricingDetails} from '../../types/pricings'
import {isFeatureEnabled} from '@github-ui/feature-flags'

interface Props {
  budgetData: Budget
  hasBudgetWritePermissions: boolean
  deleteBudget: (budgetUuid: string) => void
  enabledProducts?: Product[]
  enabledSkus?: PricingDetails[]
  copilotIapSubscription: boolean
}

function IconType({type}: {type: string}) {
  if (type === BUDGET_SCOPE_ORGANIZATION) {
    return <OrganizationIcon size={16} />
  } else if ([BUDGET_SCOPE_ENTERPRISE, BUDGET_SCOPE_CUSTOMER].includes(type)) {
    return <GlobeIcon size={16} />
  } else if (type === BUDGET_SCOPE_REPOSITORY) {
    return <RepoIcon size={16} />
  }
  return <CreditCardIcon size={16} />
}

export default function BudgetData({
  budgetData,
  hasBudgetWritePermissions,
  deleteBudget,
  enabledProducts,
  enabledSkus,
  copilotIapSubscription,
}: Props) {
  const {addToast} = useToastContext()
  const {path: editBudgetPath} = useRoute(EDIT_BUDGET_ROUTE, {budgetUUID: budgetData.uuid})
  const {path: deletePath} = useRoute(UPSERT_BUDGET_ROUTE, {budgetUUID: budgetData.uuid})
  const {path: editCostCenterPath} = useRoute(EDIT_COST_CENTER_ROUTE, {costCenterUUID: budgetData.targetId})
  const {isOrganizationRoute, isUserRoute} = useContext(PageContext)
  const copilotPremiumSKUEnabled = isFeatureEnabled('billingplatform_copilot_premium_sku')
  const isCopilotPremiumRequest = budgetData.pricingTargetId === CopilotPremiumRequestSku
  const [showIAPMessage, setShowIAPMessage] = useState(false)
  const navigate = useNavigate()

  async function handleDeleteBudget() {
    try {
      const {ok, data} = await doRequest(HTTPMethod.DELETE, deletePath, {})
      if (ok) {
        deleteBudget(budgetData.uuid)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'success',
          message: 'Budget deleted',
          role: 'status',
        })
      } else {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: `${data.error ? data.error : 'Unable to delete budget'}`,
          role: 'alert',
        })
      }
    } catch {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: 'Unable to delete budget',
        role: 'alert',
      })
    }
  }
  async function handleEditBudget() {
    const isZeroTargetAmount = budgetData.targetAmount === 0

    if (copilotIapSubscription && isCopilotPremiumRequest && isZeroTargetAmount) {
      setShowIAPMessage(true)
      return
    }

    navigate(editBudgetPath)
  }

  function fullTargetType(type: string) {
    if (type === BUDGET_SCOPE_ORGANIZATION) {
      return 'Organization'
    } else if (type === BUDGET_SCOPE_REPOSITORY) {
      return 'Repository'
    } else if (type === BUDGET_SCOPE_ENTERPRISE) {
      return 'Enterprise'
    } else if (type === ResourceType.CostCenterResource) {
      return 'Cost center'
    } else if (type === BUDGET_SCOPE_CUSTOMER) {
      if (isOrganizationRoute) {
        return 'Organization'
      } else if (isUserRoute) {
        return 'Account'
      } else {
        return 'Enterprise'
      }
    }
    return ''
  }

  function getFriendlyName(pricingTargetType?: BudgetPricingTargetType, pricingTargetId?: string): string {
    if (!enabledProducts || !enabledSkus || !pricingTargetId) return ''
    switch (pricingTargetType) {
      case BudgetPricingTargetType.ProductPricing: {
        return enabledProducts.find(product => product.name === pricingTargetId)?.friendlyProductName ?? ''
      }
      case BudgetPricingTargetType.SkuPricing: {
        return enabledSkus.find(sku => sku.sku === pricingTargetId)?.friendlyName ?? ''
      }
      default:
        return ''
    }
  }

  // We want to hide budgets for Copilot Premium Requests until the the phased rollout for
  // premium requests has started
  if (!copilotPremiumSKUEnabled && isCopilotPremiumRequest) {
    return null
  } else {
    return (
      <>
        <Box
          as="tr"
          key={budgetData.uuid}
          sx={{
            ...tableRowStyle,
            ...tableRowStyleRowtoCol,
          }}
        >
          <Box as="td" sx={{display: 'flex', flex: 2.5, maxWidth: '320px', whiteSpace: 'normal'}}>
            <Box sx={{pr: [0, 3, 3], display: ['none', 'flex', 'flex'], alignItems: 'center'}}>
              <IconType type={budgetData.targetType} />
            </Box>
            <Box sx={{display: 'flex', alignItems: [null, 'center', 'center'], width: ['100%', '50%', 'auto']}}>
              <Box sx={tableDataCellStyle}>
                <Text sx={{fontSize: 0, color: 'fg.muted', mr: [1, 0, 0]}}>
                  {fullTargetType(budgetData.targetType)}
                </Text>
                {budgetData.targetType === ResourceType.CostCenterResource && !budgetData.targetName ? (
                  <Link href={editCostCenterPath} sx={{color: 'btn.text'}}>
                    <Text sx={{fontWeight: 'normal'}}>View Details</Text>
                  </Link>
                ) : (
                  <Text sx={{fontWeight: 'bold', fontSize: 1}}>{budgetData.targetName}</Text>
                )}
              </Box>
              <BudgetLabel
                budgetCurrentAmount={budgetData.currentAmount}
                budgetTargetAmount={budgetData.targetAmount}
              />
            </Box>
          </Box>
          <Box as="td" sx={{flex: 2.5, ml: [0, 2, 2], mr: [0, 1, 2]}}>
            <Box sx={tableDataCellStyle}>
              <Text sx={{fontSize: 0, color: 'fg.muted'}}>
                {budgetData.pricingTargetType === BudgetPricingTargetType.ProductPricing ? 'Product' : 'SKU'}
              </Text>
              <Text sx={{fontSize: 1}}>
                {getFriendlyName(budgetData.pricingTargetType, budgetData.pricingTargetId)}
              </Text>
            </Box>
          </Box>
          <Box as="td" sx={{flex: 1, ml: [0, 1, 2], mr: [0, 2, 2]}}>
            <Box sx={tableDataCellStyle}>
              <Text sx={{fontSize: 0, color: 'fg.muted'}}>Alerts</Text>
              <Text sx={{fontSize: 1}}>{budgetData.alertEnabled ? 'On' : 'Off'}</Text>
            </Box>
          </Box>
          <Box as="td" sx={{flex: 3, minWidth: '180px'}}>
            <Box sx={{display: 'flex', flexDirection: 'column', width: ['100%', 'auto', 'auto']}}>
              <Box sx={{display: 'flex'}}>
                <Box sx={{display: 'flex', flexDirection: 'column', justifyContent: 'center', flex: '1'}}>
                  <BudgetProgressBar
                    budgetCurrentAmount={budgetData.currentAmount}
                    budgetTargetAmount={budgetData.targetAmount}
                  />
                  <Box sx={{display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap'}}>
                    <div>
                      <BudgetWarningIcon isOverBudget={budgetData.currentAmount > budgetData.targetAmount} />
                      <Text sx={{fontWeight: 'normal'}}>{formatMoneyDisplay(budgetData.currentAmount)}</Text>
                      &nbsp;
                      <Text sx={{fontWeight: 'light', fontSize: 0}}>spent</Text>
                    </div>
                    <div>
                      <Text sx={{fontWeight: 'normal'}}>{formatMoneyDisplay(budgetData.targetAmount)}</Text>&nbsp;
                      <Text sx={{fontWeight: 'light', fontSize: 0}}>budget</Text>
                    </div>
                  </Box>
                </Box>
                {hasBudgetWritePermissions && (
                  <BudgetActionMenu
                    budgetId={budgetData.uuid}
                    productName={getFriendlyName(budgetData.pricingTargetType, budgetData.pricingTargetId)}
                    targetType={budgetData.targetType}
                    targetName={budgetData.targetName}
                    onEditClick={handleEditBudget}
                    onDeleteClick={handleDeleteBudget}
                  />
                )}
              </Box>
            </Box>
          </Box>
        </Box>
        {showIAPMessage && (
          <Box
            as="tr"
            sx={{
              ...tableRowStyle,
              ...tableRowStyleRowtoCol,
              borderTop: 'none',
            }}
            data-testid="copilot-iap-error-message"
          >
            <Box as="td" sx={{display: 'flex', flex: 3, whiteSpace: 'normal'}}>
              <InlineMessage variant="critical">
                Your Copilot premium request budget cannot be adjusted because your subscription was made via mobile
                in-app purchase. Manage your subscription in App Store settings.
              </InlineMessage>
            </Box>
          </Box>
        )}
      </>
    )
  }
}
