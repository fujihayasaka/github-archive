import {borderTop, fixedWidthCell, identifierCell, tableStyle, trStyle} from './style'
import {formatQuantityDisplay, getBilledAmount} from '../../../utils/usage'

import {Box} from '@primer/react'
import type {ProductUsageLineItem} from '../../../types/usage'
import {formatMoneyDisplay} from '../../../utils/money'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {isLicensedSkuWithDailyEmissions} from '../../../utils'

interface Props {
  data: ProductUsageLineItem[]
}

export default function UsageSubTable({data}: Props) {
  const showLicenseUIChanges = useFeatureFlag('billing_proration_for_licensed_products')
  // sort by SKU name to preserve order of row entries between sub table rows
  const sortedData = data.sort((a, b) => {
    return a.friendlySkuName.localeCompare(b.friendlySkuName)
  })

  const getRowCost = (row: ProductUsageLineItem) => {
    // for licensed products with daily emissions, we show a prorated cost equal to the monthly cost / days in the month of usage
    if (showLicenseUIChanges && isLicensedSkuWithDailyEmissions(row) && row.dailyLicenseCost) {
      return row.dailyLicenseCost
    } else return row.appliedCostPerQuantity
  }

  return (
    <Box sx={{...tableStyle}} data-testid="usage-sub-table">
      <Box sx={{display: 'flex'}}>
        <Box sx={{width: 56}} />
        <Box sx={{...identifierCell, color: 'fg.subtle', pl: 0, ml: -2}}>SKU</Box>
        <Box sx={{...fixedWidthCell, color: 'fg.subtle'}}>Units</Box>
        <Box sx={{...fixedWidthCell, color: 'fg.subtle'}}>Price/unit</Box>
        <Box sx={{...fixedWidthCell, color: 'fg.subtle'}}>Gross amount</Box>
        <Box sx={{...fixedWidthCell, color: 'fg.subtle'}}>Billed amount</Box>
      </Box>
      <div>
        {sortedData.map(row => {
          return (
            <Box sx={{...trStyle}} key={`sub-table-${row.product}-${row.sku}-${row.usageAt}`}>
              <Box sx={{width: 56}} />
              <Box sx={{...borderTop, ...identifierCell, pl: 0, ml: -2}} data-testid="sub-sku-td">
                {row.friendlySkuName ?? row.sku}
              </Box>
              <Box sx={{...fixedWidthCell, ...borderTop}} data-testid="sub-quantity-td">
                {formatQuantityDisplay(row, 2, showLicenseUIChanges)}
              </Box>
              <Box sx={{...fixedWidthCell, ...borderTop}} data-testid="sub-applied-cost-per-quantity-td">
                {formatMoneyDisplay(getRowCost(row), 6)}
              </Box>
              <Box sx={{...fixedWidthCell, ...borderTop}} data-testid="sub-gross-amount-td">
                {formatMoneyDisplay(row.billedAmount)}
              </Box>
              <Box sx={{...fixedWidthCell, ...borderTop}} data-testid="sub-billed-amount-td">
                {getBilledAmount(row.totalAmount)}
              </Box>
            </Box>
          )
        })}
      </div>
    </Box>
  )
}
