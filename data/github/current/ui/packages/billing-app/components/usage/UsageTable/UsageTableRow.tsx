import {Box, Details, Link, Spinner, useDetails} from '@primer/react'
import {PRODUCT_TAB_ICON_MAP, PRODUCT_TAB_TEXT_MAP} from '../../../constants/products'
import {Octicon} from '@primer/react/deprecated'
import {ChevronDownIcon, ChevronRightIcon, RepoIcon} from '@primer/octicons-react'
import type {Filters, RepoUsageLineItem, UsageLineItem} from '../../../types/usage'
import {RequestState, UsageGrouping, UsagePeriod} from '../../../enums'
import {borderTop, fixedWidthCell, identifierCell, trStyle, columnAvatarStyle} from './style'
import {formatQuantityDisplay, getBilledAmount} from '../../../utils/usage'
import {isProductUsageLineItem, isRepoUsageLineItem} from '../../../utils/types'

import {DEFAULT_GROUP_TYPE} from '../../../constants'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {UsageSubTable} from '.'
import {formatMoneyDisplay} from '../../../utils/money'
import {formatUsageDateForPeriod} from '../../../utils/date'
import {useMemo} from 'react'
import useUsageSubTableData from '../../../hooks/usage/use-usage-sub-table-data'
import styles from './UsageTableRow.module.css'
import {isLicensedSkuWithDailyEmissions} from '../../../utils'
import {applyLicenseQuantities} from '../../../utils/license-sku-usage'

const spinnerStyle = {
  mt: 3,
  mb: 3,
  mr: 'auto',
  ml: 'auto',
}

interface UsageTableRowProps {
  expandable: boolean
  rawUsage: UsageLineItem[]
  row: UsageLineItem | RepoUsageLineItem
  showPricePerUnit: boolean
  showQuantity: boolean
  filters: Filters
  isOtherUsageRow?: boolean
  isEnterpriseRoute: boolean
  codingAgentEnabled: boolean
  sparkEnabled: boolean
}

export default function UsageTableRow({
  expandable,
  rawUsage,
  row,
  showPricePerUnit,
  showQuantity,
  filters,
  isEnterpriseRoute,
  codingAgentEnabled,
  sparkEnabled,
  ...props
}: UsageTableRowProps) {
  const {getDetailsProps, open} = useDetails({closeOnOutsideClick: false})
  const {usage, requestState, netUsageItems} = useUsageSubTableData({
    lineItem: row,
    open,
    rawUsage,
    filters,
  })

  const groupType = filters?.group?.type ?? DEFAULT_GROUP_TYPE
  const periodType = filters?.period?.type ?? UsagePeriod.DEFAULT
  const licensedSkuUsage = useMemo(() => usage.filter(item => isLicensedSkuWithDailyEmissions(item)), [usage])

  const usageSubTableData = useMemo(() => {
    const getFilteredProductUsage = () =>
      usage.filter(
        usageItem =>
          isProductUsageLineItem(usageItem) && isProductUsageLineItem(row) && usageItem.product === row.product,
      )

    const shouldApplyLicensedQuantities = licensedSkuUsage.length > 0

    switch (groupType) {
      case UsageGrouping.PRODUCT: {
        // when grouping by product we can avoid an extra request to billing platform to get usage data by
        // filtering sub table usage for the current row's product
        const filteredUsage = getFilteredProductUsage()
        return shouldApplyLicensedQuantities
          ? filteredUsage.map(item => applyLicenseQuantities(item, rawUsage, filters))
          : filteredUsage
      }

      case UsageGrouping.COSTCENTER:
        return shouldApplyLicensedQuantities
          ? usage.map(item => applyLicenseQuantities(item, rawUsage, filters))
          : usage

      case UsageGrouping.ORG:
        return shouldApplyLicensedQuantities
          ? usage.map(item => applyLicenseQuantities(item, netUsageItems, filters))
          : usage

      default:
        return usage
    }
  }, [licensedSkuUsage.length, groupType, usage, row, rawUsage, filters, netUsageItems])

  const getFirstColumnContent = (): JSX.Element | null => {
    if (props.isOtherUsageRow) return <span>All other</span>

    if (isProductUsageLineItem(row)) {
      let text
      if (groupType === UsageGrouping.NONE) text = formatUsageDateForPeriod(row.usageAt, periodType)
      if (groupType === UsageGrouping.PRODUCT) {
        if (row.product === 'ghec' || row.product === 'ghas') {
          // Remove when we decide to update friendly product names for GHEC and GHAS on the usage table
          text = row.product.toUpperCase()
        } else {
          text = PRODUCT_TAB_TEXT_MAP[row.product as keyof typeof PRODUCT_TAB_TEXT_MAP]
        }
      }
      if (groupType === UsageGrouping.SKU) text = row.friendlySkuName
      if (groupType === UsageGrouping.COSTCENTER) text = row.name
      return <span>{text}</span>
    } else if (isRepoUsageLineItem(row)) {
      if (row.org.login) {
        return (
          <Link
            href={groupType === UsageGrouping.REPO ? `/${row.org.login}/${row.repo.name}` : `/${row.org.login}`}
            target="_blank"
            sx={columnAvatarStyle}
          >
            <span className="mr-2">
              {row.org.avatarSrc && isEnterpriseRoute ? (
                <GitHubAvatar square src={row.org.avatarSrc} size={16} />
              ) : (
                <RepoIcon className="color-fg-muted" />
              )}
            </span>
            <span>
              {groupType === UsageGrouping.ORG
                ? row.org.name
                : isEnterpriseRoute
                  ? `${row.org.name}/${row.repo.name}`
                  : row.repo.name}
            </span>
          </Link>
        )
      } else {
        return <span>{groupType === UsageGrouping.ORG ? row.org.name : `${row.org.name}/${row.repo.name}`}</span>
      }
    } else return null
  }

  const getFirstColumnIcon = (): JSX.Element | null => {
    if (isProductUsageLineItem(row) && groupType === UsageGrouping.PRODUCT) {
      const IconComponent = PRODUCT_TAB_ICON_MAP[row.product as keyof typeof PRODUCT_TAB_ICON_MAP]
      return IconComponent ? <IconComponent className="color-fg-muted" /> : null
    }
    return null
  }

  const getRowCost = () => {
    if (isLicensedSkuWithDailyEmissions(row) && row.dailyLicenseCost) {
      return row.dailyLicenseCost
    } else return row.appliedCostPerQuantity
  }

  const getRowContent = (): JSX.Element => {
    return (
      <Box sx={{...trStyle}}>
        {expandable && (
          // Make the clickable area a bit larger
          <Details {...getDetailsProps()} className={styles.Details}>
            <Box
              as={'summary'}
              sx={{p: 2}}
              title={open ? 'Hide Usage Breakdown' : 'Show Usage Breakdown'}
              data-testid={'usage-details'}
            >
              <Octicon icon={open ? ChevronDownIcon : ChevronRightIcon} />
            </Box>
          </Details>
        )}
        {expandable ? (
          <Box sx={{...identifierCell, ml: -2}} data-testid="identifier-td">
            {getFirstColumnIcon() && <span style={{marginRight: '8px'}}>{getFirstColumnIcon()}</span>}
            {getFirstColumnContent()}
          </Box>
        ) : (
          <Box sx={{...identifierCell}} data-testid="identifier-td">
            {getFirstColumnContent()}
          </Box>
        )}
        {showQuantity && (
          <Box sx={{...fixedWidthCell, color: 'fg.muted'}} data-testid="quantity-td">
            {formatQuantityDisplay(row, 2)}
          </Box>
        )}
        {showPricePerUnit && (
          <Box sx={{...fixedWidthCell, color: 'fg.muted'}} data-testid="applied-cost-per-quantity-td">
            {formatMoneyDisplay(getRowCost(), 6)}
          </Box>
        )}
        <Box sx={{...fixedWidthCell, color: 'fg.muted'}} data-testid="gross-amount-td">
          {formatMoneyDisplay(row.billedAmount)}
        </Box>
        <Box sx={{...fixedWidthCell, fontWeight: 'bold'}} data-testid="billed-amount-td">
          {getBilledAmount(row.totalAmount)}
        </Box>
      </Box>
    )
  }

  const testId = useMemo(() => {
    if (isProductUsageLineItem(row)) {
      if (groupType === UsageGrouping.NONE) return `usage-date-${formatUsageDateForPeriod(row.usageAt, periodType)}`
      if (groupType === UsageGrouping.PRODUCT) return `usage-${row.product}`
      if (groupType === UsageGrouping.SKU) return `usage-${row.sku}`
      if (groupType === UsageGrouping.COSTCENTER) return `usage-${row.entityId}`
    } else if (isRepoUsageLineItem(row)) {
      if (groupType === UsageGrouping.ORG) return `usage-${row.org.name}`
      if (groupType === UsageGrouping.REPO) return `usage-${row.org.name}-${row.repo.name}`
    }
  }, [row, groupType, periodType])

  return (
    <Box sx={borderTop} data-testid={testId}>
      {getRowContent()}
      <Box sx={trStyle}>
        {requestState === RequestState.LOADING && <Spinner sx={spinnerStyle} />}
        {open && requestState === RequestState.IDLE && (
          <UsageSubTable data={usageSubTableData} codingAgentEnabled={codingAgentEnabled} sparkEnabled={sparkEnabled} />
        )}
      </Box>
    </Box>
  )
}
