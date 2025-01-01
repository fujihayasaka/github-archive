import {useEffect, useMemo, useState} from 'react'
import {Box, Pagination} from '@primer/react'
import {useSearchParams} from '@github-ui/use-navigate'

import {UsageTableRow, UsageTableRowSkeleton} from '.'
import {ErrorComponent} from '../..'

import {containerStyle, fixedWidthCell, identifierCell, tableStyle, theadStyle, trStyle} from './style'
import {DEFAULT_GROUP_TYPE, GROUP_BY_ORG_TYPE, GROUP_BY_REPO_TYPE, USAGE_LINE_ITEMS_PER_PAGE} from '../../../constants'
import {RequestState, UsageGrouping, UsagePeriod} from '../../../enums'
import {groupLineItems, sortByUsageAtDesc} from '../../../utils/group'
import {isProductUsageLineItem, isRepoUsageLineItem} from '../../../utils/types'
import {useUsageTableData} from '../../../hooks/usage'

import type {Filters, ProductUsageLineItem, UsageLineItem} from '../../../types/usage'

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
}

export const getPageCount = (totalLineItemsCount: number, dataLength: number): number => {
  // While we are working on releasing aggregate usage, the length of each page may vary.
  // This will be resolved in https://github.com/github/gitcoin/issues/17075
  const lineItemsCount = totalLineItemsCount ?? 0
  const lengthOfPage = dataLength ?? USAGE_LINE_ITEMS_PER_PAGE
  return Math.ceil(lineItemsCount / lengthOfPage)
}

export default function UsageTable({filters}: Props) {
  // TODO: Make filters required
  const groupType = filters.group?.type ?? DEFAULT_GROUP_TYPE
  const periodType = filters.period?.type ?? UsagePeriod.DEFAULT

  const isOrgorRepoGrouping = groupType === GROUP_BY_ORG_TYPE || groupType === GROUP_BY_REPO_TYPE

  const [searchParams] = useSearchParams()
  const initialPage = Number(searchParams.get('page')) || 1
  const [currentPage, setCurrentPage] = useState(initialPage)

  const {
    usageTableData,
    totalLineItemsCount,
    requestState: tableUsageRequestState,
  } = useUsageTableData({
    filters,
    isOrgorRepoGrouping,
    currentPage,
  })

  const pageCount = getPageCount(totalLineItemsCount, usageTableData.length)

  const usageData = usageTableData
  const usageRequestState = tableUsageRequestState

  const groupedUsage = useMemo(() => {
    return groupType === UsageGrouping.NONE
      ? groupLineItems(usageData, groupType, periodType).sort(sortByUsageAtDesc)
      : // SKU grouping does not use sub table data since there are no rows to expand. With this, we just need to sort the rows by SKU
        groupType === UsageGrouping.SKU
        ? (groupLineItems(usageData, groupType) as ProductUsageLineItem[]).sort((a, b) => {
            return a?.friendlySkuName.localeCompare(b?.friendlySkuName)
          })
        : groupLineItems(usageData, groupType)
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

  useEffect(() => {
    setCurrentPage(searchParams.get('page') ? Number(searchParams.get('page')) : 1)
  }, [filters, searchParams])

  const onPageChange = (e: React.MouseEvent, page: number) => {
    e.preventDefault()
    setCurrentPage(page)
    const params = new URLSearchParams(window.location.search)
    params.set('page', page.toString())
    history.pushState(null, '', `?${params.toString()}`)
  }

  if (usageRequestState === RequestState.ERROR) {
    return <ErrorComponent sx={{aspectRatio}} testid="usage-loading-error" text="Something went wrong" />
  }

  // don't return anything if we made a request and there is no data
  if (usageRequestState === RequestState.IDLE && groupedUsage.length === 0) {
    return null
  }

  return (
    <div>
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
            {[RequestState.INIT, RequestState.LOADING].includes(usageRequestState) && (
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
                />
              ))}
          </div>
        </Box>
      </Box>
      {isOrgorRepoGrouping && pageCount > 1 && (
        <Pagination pageCount={pageCount} currentPage={currentPage} onPageChange={onPageChange} />
      )}
    </div>
  )
}
