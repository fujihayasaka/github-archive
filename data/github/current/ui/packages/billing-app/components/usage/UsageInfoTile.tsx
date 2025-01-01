import toUpper from 'lodash-es/toUpper'
import toLower from 'lodash-es/toLower'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {Box, Heading, Link, Text} from '@primer/react'

import {ErrorComponent} from '..'

import {RequestState, UsagePeriod} from '../../enums'
import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle} from '../../utils/style'
import useRoute from '../../hooks/use-route'
import {ENTERPRISE_LICENSING_BASE_ROUTE, USAGE_ROUTE} from '../../routes'
import {GROUP_BY_SKU_TYPE, Products} from '../../constants'
import type {Filters} from '../../types/usage'

export const UsageInfoTileVariant = {
  amountSpent: 'AMOUNT_SPENT',
  quantityUsed: 'QUANTITY_USED',
} as const

export type UsageInfoTileVariant = (typeof UsageInfoTileVariant)[keyof typeof UsageInfoTileVariant]

interface UsageInfoTileProps {
  filters: Filters
  isCopilotStandalone: boolean
  productName: string
  requestState: RequestState
  totalSpendOrSeats: number
  variant: UsageInfoTileVariant
}

const isLoadingStates = new Set<RequestState>([RequestState.INIT, RequestState.LOADING])

export default function UsageInfoTile({
  filters,
  isCopilotStandalone,
  productName,
  requestState,
  totalSpendOrSeats,
  variant,
}: UsageInfoTileProps) {
  const {path: usageUrl} = useRoute(
    USAGE_ROUTE,
    {},
    {
      group: GROUP_BY_SKU_TYPE.toString(),
      period: filters?.period?.type?.toString() ?? UsagePeriod.DEFAULT.toString(),
      query: `product:${filters.product}`,
    },
  )
  const {path: enterpriseLicensingUrl} = useRoute(ENTERPRISE_LICENSING_BASE_ROUTE)

  function toTitleCase(str: string): string {
    return str
      .split(' ')
      .map(word => toUpper(word.charAt(0)) + toLower(word.slice(1)))
      .join(' ')
  }

  const capitalizedProductName = toTitleCase(productName)
  function defaultTitle(): string {
    if (variant === UsageInfoTileVariant.amountSpent) {
      return `${capitalizedProductName} usage`
    } else {
      return `Licenses used`
    }
  }

  function defaultSubtitle() {
    if (variant === UsageInfoTileVariant.amountSpent) {
      return `Total spend on ${capitalizedProductName} for the selected timeframe, excluding applicable discounts.`
    } else {
      return 'Showing total unique licenses billed for your enterprise. Actual billed amount for each license is prorated based on when it is added during the billing cycle.'
    }
  }

  function spotlightedValue() {
    if (variant === UsageInfoTileVariant.amountSpent) {
      return formatMoneyDisplay(totalSpendOrSeats)
    } else {
      return totalSpendOrSeats.toFixed(2)
    }
  }

  function viewDetailsLink() {
    if (variant === UsageInfoTileVariant.quantityUsed && filters.product === Products.copilot && !isCopilotStandalone) {
      return null
    }
    const url = variant === UsageInfoTileVariant.amountSpent ? usageUrl : enterpriseLicensingUrl
    return (
      <Link className="f6" inline href={url}>
        View details
      </Link>
    )
  }

  function learnMore() {
    if (variant === UsageInfoTileVariant.amountSpent) {
      return null
    }
    return (
      <Link
        inline
        href="https://docs.github.com/enterprise-cloud@latest/billing/using-the-new-billing-platform/about-usage-based-billing-for-licenses"
      >
        Learn more
      </Link>
    )
  }

  return (
    <Box sx={boxStyle}>
      <div className="d-flex flex-justify-between">
        <Heading as="h3" sx={cardHeadingStyle}>
          {defaultTitle()}
        </Heading>
        {viewDetailsLink()}
      </div>
      {isLoadingStates.has(requestState) && (
        <>
          <LoadingSkeleton variant="rounded" height="36px" />
          <LoadingSkeleton variant="rounded" height="xl" />
        </>
      )}
      {requestState === RequestState.ERROR && (
        <ErrorComponent sx={{border: 0}} testid={`${productName}-usage-loading-error`} text="Something went wrong" />
      )}
      {requestState === RequestState.IDLE && (
        <Text sx={{display: 'block', fontSize: 4, lineHeight: '36px'}} data-testid="number-display">
          {spotlightedValue()}
        </Text>
      )}
      <Text as="p" sx={{mb: 0, color: 'fg.muted'}}>
        {defaultSubtitle()}
        {` `}
        {learnMore()}
      </Text>
    </Box>
  )
}
