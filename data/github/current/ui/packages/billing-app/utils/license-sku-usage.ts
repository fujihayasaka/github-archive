import type {Filters, ProductUsageLineItem, UsageLineItem} from '../types/usage'
import {isProductUsageLineItem, isLicensedSkuWithDailyEmissions} from '../utils'
import {UsagePeriod, UsageGrouping} from '../enums'

/**
 * Applies license quantities to usage items based on the current filters.
 *
 * @param usageItem - The product usage line item to apply license quantities to.
 * @param allUsage - All usage line items.
 * @param filters - The filters currently applied to the usage data.
 * @returns The updated product usage line item with license quantities applied.
 */
export function applyLicenseQuantities(
  usageItem: ProductUsageLineItem,
  allUsage: UsageLineItem[],
  filters: Filters,
): ProductUsageLineItem {
  // Early return if the item isn't a licensed SKU with daily emissions
  if (!isLicensedSkuWithDailyEmissions(usageItem)) {
    return usageItem
  }

  const licensedSkuUsage = allUsage.filter(isLicensedSkuWithDailyEmissions) as ProductUsageLineItem[]
  const periodType = filters.period?.type ?? UsagePeriod.THIS_MONTH
  const isGroupedByCostCenter = filters.group?.type === UsageGrouping.COSTCENTER

  // Skip license calculations for periods other than this month or last month
  if (periodType !== UsagePeriod.THIS_MONTH && periodType !== UsagePeriod.LAST_MONTH) {
    return usageItem
  }

  // Aggregate the unique days in the month that each SKU/entity combination has usage for
  const daysUsedByEntitySku = licensedSkuUsage.reduce(
    (acc, lineItem) => {
      const sku = isProductUsageLineItem(lineItem) && lineItem.sku
      if (!sku) return acc

      const entityId = lineItem.entityId
      const key = `${entityId}:${sku}`

      const usageDate = new Date(lineItem.usageAt).toISOString().split('T')[0] // Extract the date part
      acc[key] = acc[key] || new Set()
      if (usageDate) {
        acc[key].add(usageDate)
      }
      return acc
    },
    {} as {[key: string]: Set<string>},
  )

  const lookupKey = isGroupedByCostCenter ? `${usageItem.entityId}:${usageItem.sku}` : usageItem.sku
  let daysUsedInMonth: number

  if (isGroupedByCostCenter) {
    daysUsedInMonth = daysUsedByEntitySku[lookupKey]?.size ?? 1
  } else {
    const uniqueDaysBySku: {[sku: string]: Set<string>} = {}

    for (const [key, daysSet] of Object.entries(daysUsedByEntitySku)) {
      const sku = key.split(':')[1] // Extract SKU from the key
      if (sku) {
        uniqueDaysBySku[sku] = uniqueDaysBySku[sku] || new Set()
        for (const day of daysSet) {
          uniqueDaysBySku[sku].add(day)
        }
      }
    }

    daysUsedInMonth = uniqueDaysBySku[lookupKey]?.size ?? 1
  }

  const dailyLicenseQuantity = usageItem.dailyLicenseQuantity ?? 0
  const dailyLicenseCost = usageItem.dailyLicenseCost ?? 0

  return {
    ...usageItem,
    /*
     * Calculate the average number of licenses assigned month-to-date. Important for cases where licenses
     * are assigned partway through a month.
     * Example: If 1 seat is assigned on April 1 and 2 more are added on April 2, the sum of the dailyLicenseQuantity
     * is 3 seats / 2 days of usage, resulting in 1.5 seats/day displayed in the UI when looking at a monthly grouped view on April 2nd
     */
    dailyLicenseQuantity: dailyLicenseQuantity / daysUsedInMonth,
    /*
     * Calculate the price / unit based on the number of days a sku was used in the month.
     * Example: For a SKU that's $39 a month per seat on April 3rd and there's usage for all 3 days in April:
     * $39 / 30 days = $1.30/day - this is the dailyLicenseCost for April, calculated in billing platform
     * $1.30 * 3 days of usage in April = $3.90 - this is the unit/price on April 3rd
     */
    dailyLicenseCost: dailyLicenseCost * daysUsedInMonth,
  }
}
