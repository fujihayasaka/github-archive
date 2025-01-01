import {useMemo} from 'react'
import {Box, Heading, Text} from '@primer/react'

import {UsageTableRow, UsageTableRowSkeleton} from '.'
import {ErrorComponent} from '../..'

import {containerStyle, fixedWidthCell, identifierCell, tableStyle, theadStyle, trStyle} from './style'
import {DEFAULT_GROUP_TYPE} from '../../../constants'
import {RequestState, UsageGrouping, UsagePeriod} from '../../../enums'
import {groupLineItems, sortByUsageAtDesc, sortByGrossAmountDesc} from '../../../utils/group'
import {isProductUsageLineItem, isRepoUsageLineItem} from '../../../utils/types'
import {useUsageTableData} from '../../../hooks/usage'
import {getPeriodText} from '../../../utils'
import styles from './UsageTable.module.css'

import type {Filters, NetUsageLineItem, ProductUsageLineItem, UsageLineItem} from '../../../types/usage'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

const aspectRatio = '3 / 1'

const getRowKey = (lineItem: UsageLineItem, groupType: UsageGrouping): string => {
  if (groupType === UsageGrouping.NONE) return lineItem.usageAt
  if (groupType === UsageGrouping.COSTCENTER) return lineItem.entityId
  if (isRepoUsageLineItem(lineItem)) return `${lineItem.org.name}-${lineItem.repo.name}`
  else if (isProductUsageLineItem(lineItem)) return lineItem.sku
  else return ''
}

interface Props {
  filters: Filters
  isEnterpriseRoute: boolean
}

const loadingStates = new Set<RequestState>([RequestState.INIT, RequestState.LOADING])

export default function UsageTable({filters, isEnterpriseRoute}: Props) {
  const groupType = filters.group?.type ?? DEFAULT_GROUP_TYPE
  const periodType = filters.period?.type ?? UsagePeriod.DEFAULT
  const showLicenseUIChanges = useFeatureFlag('billing_proration_for_licensed_products')

  const {
    otherUsage,
    usageTableData,
    requestState: tableUsageRequestState,
  } = useUsageTableData({
    filters,
  })

  const usageData = usageTableData
  const usageRequestState = tableUsageRequestState

  const groupedUsage = useMemo(() => {
    if (groupType === UsageGrouping.NONE) {
      return groupLineItems(usageData, groupType, periodType).sort(sortByUsageAtDesc)
    } else if (groupType === UsageGrouping.SKU) {
      return (groupLineItems(usageData, groupType) as ProductUsageLineItem[]).sort((a, b) => {
        return a?.friendlySkuName.localeCompare(b?.friendlySkuName)
      })
    } else if (groupType === UsageGrouping.REPO || groupType === UsageGrouping.ORG) {
      return groupLineItems(usageData, groupType).sort(sortByGrossAmountDesc)
    } else {
      return groupLineItems(usageData, groupType)
    }
  }, [usageData, groupType, periodType])

  const getFirstColumnHeader = (): string => {
    switch (groupType) {
      case UsageGrouping.NONE:
        return 'Date'
      case UsageGrouping.ORG:
        return 'Organizations'
      case UsageGrouping.PRODUCT:
        return 'Products'
      case UsageGrouping.REPO:
        return 'Repositories'
      case UsageGrouping.SKU:
        return 'SKUs'
      case UsageGrouping.COSTCENTER:
        return 'Cost Centers'
      default:
        return ''
    }
  }

  const showQuantity = groupType === UsageGrouping.SKU
  const showPricePerUnit = groupType === UsageGrouping.SKU
  const expandable = groupType !== UsageGrouping.SKU

  if (usageRequestState === RequestState.ERROR) {
    return <ErrorComponent sx={{aspectRatio}} testid="usage-loading-error" text="Something went wrong" />
  }

  // don't return anything if we made a request and there is no data
  if (usageRequestState === RequestState.IDLE && groupedUsage.length === 0) {
    return null
  }

  return (
    <div>
      {showLicenseUIChanges && (
        <div className={styles.usageTableHeaderContainer}>
          <Heading as="h3" variant="small">
            Usage breakdown
          </Heading>
          <Text size="small" className={styles.hintText}>{`Usage for ${getPeriodText(
            filters.period,
          )}. For license-based products, the price/unit is a prorated portion of the monthly price.`}</Text>
        </div>
      )}
      <Box sx={containerStyle}>
        <Box sx={tableStyle} data-testid="usage-table">
          <Box sx={theadStyle}>
            <Box sx={trStyle}>
              <Box sx={identifierCell}>{getFirstColumnHeader()}</Box>
              {showQuantity && <Box sx={fixedWidthCell}>Units</Box>}
              {showPricePerUnit && <Box sx={fixedWidthCell}>Price/unit</Box>}
              <Box sx={fixedWidthCell}>Gross amount</Box>
              <Box sx={fixedWidthCell}>Billed amount</Box>
            </Box>
          </Box>
          <div data-testid="usage-table-rows">
            {loadingStates.has(usageRequestState) && (
              <span data-testid="usage-table-row-skeletons">
                <UsageTableRowSkeleton showQuantity={showQuantity} showPricePerUnit={showPricePerUnit} />
                <UsageTableRowSkeleton showQuantity={showQuantity} showPricePerUnit={showPricePerUnit} />
                <UsageTableRowSkeleton showQuantity={showQuantity} showPricePerUnit={showPricePerUnit} />
              </span>
            )}
            {usageRequestState === RequestState.IDLE &&
              groupedUsage.map(row => (
                <UsageTableRow
                  expandable={expandable}
                  key={getRowKey(row, groupType)}
                  rawUsage={usageData}
                  row={row}
                  showPricePerUnit={showPricePerUnit}
                  showQuantity={showQuantity}
                  filters={filters}
                  isEnterpriseRoute={isEnterpriseRoute}
                />
              ))}

            {otherUsage.length > 0 && (
              <UsageTableRow
                expandable={false}
                rawUsage={[]}
                row={
                  {
                    billedAmount: otherUsage.reduce((acc, curr) => acc + curr.billedAmount, 0),
                    totalAmount: otherUsage.reduce((acc, curr) => acc + curr.netAmount, 0),
                  } as NetUsageLineItem
                }
                showPricePerUnit={false}
                showQuantity={false}
                filters={filters}
                isEnterpriseRoute={isEnterpriseRoute}
                isOtherUsageRow
              />
            )}
          </div>
        </Box>
      </Box>
    </div>
  )
}
