import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {Box, Heading, Link, ProgressBar, Text} from '@primer/react'

import {ErrorComponent} from '..'

import {BUDGET_SCOPE_ENTERPRISE, GROUP_BY_SKU_TYPE, Products} from '../../constants'
import type {UsagePeriod} from '../../enums'
import {DiscountTargetType, DiscountType, RequestState} from '../../enums'
import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle} from '../../utils/style'

import type {Budget} from '../../types/budgets'
import type {EnabledProduct} from '../../types/products'
import type {UsageLineItem} from '../../types/usage'
import {getTextForDiscount} from '../../utils'
import {useDiscounts} from '../../hooks/discount'
import useRoute from '../../hooks/use-route'
import {USAGE_ROUTE} from '../../routes'

import styles from './DefaultUsageCard.module.css'

const cardStyle = {
  ...boxStyle,
  mb: 3,
}

const spendingContainerStyle = {
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'space-between',
}

interface DefaultUsageCardProps {
  budgets: Budget[]
  isOrgAdmin: boolean
  product: EnabledProduct
  requestState: RequestState
  usage: UsageLineItem[]
  usagePeriod: UsagePeriod
}

const isLoadingStates = new Set<RequestState>([RequestState.INIT, RequestState.LOADING])
export default function DefaultUsageCard({
  budgets,
  isOrgAdmin,
  product,
  requestState,
  usage,
  usagePeriod,
}: DefaultUsageCardProps) {
  const {path: usageUrl} = useRoute(
    USAGE_ROUTE,
    {},
    {
      group: GROUP_BY_SKU_TYPE.toString(),
      period: usagePeriod.toString(),
      query: `product:${product.name}`,
    },
  )
  const enterpriseBudget = budgets.find(b => b.targetType === BUDGET_SCOPE_ENTERPRISE)
  const budgetAmount = enterpriseBudget?.targetAmount || 0
  const hasEnterpriseBudget = budgetAmount > 0

  const {discountTargetAmounts} = useDiscounts({enabledProducts: [product]})
  let actionsMinutesDiscountText = ''

  if (product.name === Products.actions) {
    const currentDiscountAmount =
      discountTargetAmounts[DiscountTargetType.SKU_ACTIONS_MINUTES]?.[DiscountType.FixedAmount]
    if (currentDiscountAmount) {
      actionsMinutesDiscountText = getTextForDiscount(
        currentDiscountAmount,
        DiscountTargetType.SKU_ACTIONS_MINUTES,
        DiscountType.FixedAmount,
      ).join(' ')
    }
  }

  const totalActual = usage.reduce((acc, lineItem) => acc + (lineItem.billedAmount ?? 0), 0)
  const totalDiscount = usage.reduce((acc, lineItem) => acc + (lineItem.discountAmount ?? 0), 0)
  const totalBilled = usage.reduce((acc, lineItem) => acc + (lineItem.totalAmount ?? 0), 0)

  const usagePercentage = totalActual && budgetAmount > 0 ? (totalActual / budgetAmount) * 100 : 0

  return (
    <Box sx={cardStyle}>
      <div className="d-flex flex-justify-between">
        <Heading as="h3" sx={cardHeadingStyle}>
          {product.friendlyProductName} usage
        </Heading>
        <Link className="f6" inline href={usageUrl}>
          View details
        </Link>
      </div>
      <>
        <Box sx={spendingContainerStyle}>
          <div>
            {isLoadingStates.has(requestState) && <LoadingSkeleton variant="rounded" height="36px" />}
            {requestState === RequestState.ERROR && (
              <ErrorComponent
                sx={{border: 0}}
                testid={`${product.name}-usage-loading-error`}
                text="Something went wrong"
              />
            )}
            {requestState === RequestState.IDLE && (
              <TotalTextBox
                isOrgAdmin={isOrgAdmin}
                totalActual={totalActual}
                totalDiscount={totalDiscount}
                totalBilled={totalBilled}
              />
            )}
            {!isOrgAdmin && hasEnterpriseBudget && (
              <ProgressBar
                bg={usagePercentage < 100 ? 'accent.emphasis' : 'danger.emphasis'}
                progress={usagePercentage}
                aria-valuenow={usagePercentage}
                aria-label={`${product.friendlyProductName} usage`}
                data-testid={`${product.name}-usage`}
                className={styles.ProgressBar}
              />
            )}
            {!isOrgAdmin && product.name === Products.actions && (
              <Text as="p" sx={{mb: 0, color: 'fg.muted'}}>
                Usage for Actions and Actions Runners. {actionsMinutesDiscountText}.
              </Text>
            )}
          </div>
        </Box>
      </>
    </Box>
  )
}

interface TotalTextBoxProps {
  isOrgAdmin: boolean
  totalActual: number
  totalDiscount: number
  totalBilled: number
}

function TotalTextBox({isOrgAdmin, totalActual, totalDiscount, totalBilled}: TotalTextBoxProps): JSX.Element {
  if (isOrgAdmin) {
    return (
      <Box sx={{display: 'flex', alignItems: 'flex-end'}}>
        <Text sx={{display: 'block', fontSize: 4, lineHeight: '36px', mr: 2}}>{formatMoneyDisplay(totalActual)}</Text>
        <Text sx={{color: 'fg.subtle', lineHeight: '28px'}}>spent </Text>
      </Box>
    )
  }

  return (
    <Box sx={{display: 'flex', alignItems: 'flex-end', flexWrap: 'wrap'}} data-testid="actions-totals">
      <Text sx={{display: 'block', fontSize: 4, lineHeight: '36px', mr: 2}}>{formatMoneyDisplay(totalActual)}</Text>
      <Text sx={{color: 'fg.subtle', lineHeight: '28px', mr: 2}}>consumed usage - </Text>
      <Text sx={{display: 'block', fontSize: 4, lineHeight: '36px', mr: 2}}>{formatMoneyDisplay(totalDiscount)}</Text>
      <Text sx={{color: 'fg.subtle', lineHeight: '28px', mr: 2}}>in discounts = </Text>
      <Text sx={{display: 'block', fontSize: 4, lineHeight: '36px', mr: 2}}>{formatMoneyDisplay(totalBilled)}</Text>
      <Text sx={{color: 'fg.subtle', lineHeight: '28px'}}>in billable usage </Text>
    </Box>
  )
}
