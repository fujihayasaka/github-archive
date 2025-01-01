import {useNetUsageData} from '../../hooks/usage'

import type {EnabledProduct} from '../../types/products'
import type {Filters} from '../../types/usage'
import UsageInfoTile, {UsageInfoTileVariant} from './UsageInfoTile'

interface Props {
  filters: Filters
  product: EnabledProduct
}

export function ModelsUsageContainer({filters, product}: Props) {
  const {netUsage, requestState: netUsageRequestState} = useNetUsageData({filters})

  return (
    <UsageInfoTile
      filters={filters}
      isCopilotStandalone={false}
      productName={product.name}
      requestState={netUsageRequestState}
      totalSpend={netUsage.reduce((acc, lineItem) => acc + (lineItem.totalAmount ?? 0), 0)}
      variant={UsageInfoTileVariant.amountSpent}
      codingAgentEnabled={false}
      sparkEnabled={false}
    />
  )
}
