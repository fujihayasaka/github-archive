import {Box, Heading, Link} from '@primer/react'

import {useNetUsageData} from '../../hooks/usage'

import UsageInfoTile, {UsageInfoTileVariant} from './UsageInfoTile'

import type {Filters, ProductUsageLineItem} from '../../types/usage'
import {UsagePeriod} from '../../enums'
import {boxStyle, cardHeadingStyle} from '../../utils/style'
import {useContext} from 'react'
import {PageContext} from '../../App'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {Products, CopilotPremiumRequestSku} from '../../constants'

interface Props {
  filters: Filters
  isCopilotStandalone: boolean
  productName: string
  codingAgentEnabled: boolean
  sparkEnabled: boolean
}

const cardStyle = {
  ...boxStyle,
  mb: 3,
}

const spendingContainerStyle = {
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'space-between',
}

export function SeatBasedUsageContainer({
  filters,
  isCopilotStandalone,
  productName,
  codingAgentEnabled,
  sparkEnabled,
}: Props) {
  const isUserRoute = useContext(PageContext).isUserRoute
  const {netUsage, requestState: netUsageRequestState} = useNetUsageData({filters})
  const totalSpend = netUsage.reduce((acc, lineItem) => acc + (lineItem.totalAmount ?? 0), 0)

  const totalRequests = netUsage.reduce((acc, lineItem) => {
    const sku = (lineItem as ProductUsageLineItem).sku
    if (sku === CopilotPremiumRequestSku) {
      return acc + (lineItem.quantity ?? 0)
    }
    return acc
  }, 0)

  const overage = netUsage.reduce((acc, lineItem) => {
    const sku = (lineItem as ProductUsageLineItem).sku
    if (sku === CopilotPremiumRequestSku) {
      return acc + (lineItem.totalAmount ?? 0)
    }
    return acc
  }, 0)
  const isCopilotPremiumSku = isFeatureEnabled('billingplatform_copilot_premium_sku')
  const productNameLowerCase = productName.toLowerCase()

  const billableLicenses = () => {
    // billable licenses can only be calculated when the period is current month, so ignore if a different period is selected
    if (filters.period?.type !== UsagePeriod.THIS_MONTH) {
      return 0
    }
    const today = new Date()
    const daysInMonth = new Date(today.getUTCFullYear(), today.getUTCMonth() + 1, 0).getUTCDate()
    // Find the latest line item for each sku+entity; quantity is the daily pro-rated high watermark
    const latestLineItemBySku = netUsage.reduce(
      (acc, lineItem) => {
        const sku = (lineItem as ProductUsageLineItem).sku
        const entityId = lineItem.entityId
        const key = `${entityId}:${sku}`
        if (acc[key] === undefined || acc[key].usageAt < lineItem.usageAt) {
          acc[key] = lineItem as ProductUsageLineItem
        }
        return acc
      },
      {} as {[key: string]: ProductUsageLineItem},
    )
    // Sum up the quantities for each sku and multiply by the number of days in the month to get the billable licenses
    return Object.values(latestLineItemBySku).reduce((acc, lineItem) => acc + (lineItem.quantity ?? 0), 0) * daysInMonth
  }

  return isUserRoute && productName === Products.copilot ? (
    !isCopilotPremiumSku ? (
      <Box sx={cardStyle}>
        <div className="d-flex flex-justify-between">
          <Heading as="h3" sx={cardHeadingStyle}>
            Copilot usage
          </Heading>
        </div>
        <>
          <Box sx={spendingContainerStyle}>
            <p>
              For details on your active Copilot subscription,{' '}
              <Link inline href={'/settings/billing/licensing'}>
                visit the licensing page.
              </Link>
            </p>
          </Box>
        </>
      </Box>
    ) : (
      <UsageInfoTile
        filters={filters}
        isCopilotStandalone={isCopilotStandalone}
        productName={productName}
        requestState={netUsageRequestState}
        totalSpend={overage}
        totalQuantity={totalRequests}
        variant={UsageInfoTileVariant.Overage}
        codingAgentEnabled={codingAgentEnabled}
        sparkEnabled={sparkEnabled}
      />
    )
  ) : (
    <Box
      sx={{
        display: 'grid',
        gap: 3,
        gridTemplateColumns: [
          '1',
          '1',
          '1',
          '1',
          isCopilotPremiumSku && productNameLowerCase === Products.copilot ? 'repeat(3, 1fr)' : 'repeat(2, 1fr)',
        ],
      }}
    >
      <UsageInfoTile
        filters={filters}
        isCopilotStandalone={isCopilotStandalone}
        productName={productName}
        requestState={netUsageRequestState}
        totalSpend={totalSpend}
        variant={UsageInfoTileVariant.amountSpent}
        codingAgentEnabled={codingAgentEnabled}
        sparkEnabled={sparkEnabled}
      />
      <UsageInfoTile
        filters={filters}
        isCopilotStandalone={isCopilotStandalone}
        productName={productName}
        requestState={netUsageRequestState}
        totalQuantity={billableLicenses()}
        variant={UsageInfoTileVariant.quantityUsed}
        codingAgentEnabled={codingAgentEnabled}
        sparkEnabled={sparkEnabled}
      />
      {isCopilotPremiumSku && productNameLowerCase === Products.copilot && (
        <UsageInfoTile
          filters={filters}
          isCopilotStandalone={isCopilotStandalone}
          productName={productName}
          requestState={netUsageRequestState}
          totalSpend={overage}
          totalQuantity={totalRequests}
          variant={UsageInfoTileVariant.Overage}
          codingAgentEnabled={codingAgentEnabled}
          sparkEnabled={sparkEnabled}
        />
      )}
    </Box>
  )
}
