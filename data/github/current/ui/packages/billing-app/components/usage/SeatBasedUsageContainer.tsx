import {Box, Heading, Link} from '@primer/react'

import {useNetUsageData} from '../../hooks/usage'

import UsageInfoTile, {UsageInfoTileVariant} from './UsageInfoTile'

import type {Filters} from '../../types/usage'
import {boxStyle, cardHeadingStyle} from '../../utils/style'
import {useContext} from 'react'
import {PageContext} from '../../App'

interface Props {
  filters: Filters
  isCopilotStandalone: boolean
  productName: string
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

export function SeatBasedUsageContainer({filters, isCopilotStandalone, productName}: Props) {
  const {netUsage, requestState: netUsageRequestState} = useNetUsageData({filters})
  const totalSpend = netUsage.reduce((acc, lineItem) => acc + (lineItem.totalAmount ?? 0), 0)
  const seats = netUsage.reduce((acc, lineItem) => acc + (lineItem.quantity ?? 0), 0)
  const isUserRoute = useContext(PageContext).isUserRoute

  return isUserRoute && productName === 'Copilot' ? (
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
    <Box sx={{display: 'grid', gap: 3, gridTemplateColumns: ['1', '1', '1', '1', 'repeat(2, 1fr)']}}>
      <UsageInfoTile
        filters={filters}
        isCopilotStandalone={isCopilotStandalone}
        productName={productName}
        requestState={netUsageRequestState}
        totalSpendOrSeats={totalSpend}
        variant={UsageInfoTileVariant.amountSpent}
      />
      <UsageInfoTile
        filters={filters}
        isCopilotStandalone={isCopilotStandalone}
        productName={productName}
        requestState={netUsageRequestState}
        totalSpendOrSeats={seats}
        variant={UsageInfoTileVariant.quantityUsed}
      />
    </Box>
  )
}
