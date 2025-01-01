import {applyLicenseQuantities} from '../../utils/license-sku-usage'
import {
  DEFAULT_FILTERS,
  GROUP_SELECTIONS,
  MOCK_LICENSE_SKU_USAGE_WITH_COST_CENTER_USAGE,
  PRODUCT_USAGE_LINE_ITEM,
} from '../../test-utils/mock-data'
import {groupLineItems} from '../../utils/group'
import {UsageGrouping, UsagePeriod} from '../../enums'
import type {ProductUsageLineItem} from '../../types/usage'

describe('applyLicenseQuantities', () => {
  it('should calculate licenses and days by SKU correctly for a licensed SKU line item', () => {
    const filters = {
      ...DEFAULT_FILTERS,
      group: GROUP_SELECTIONS[1], // Using the SKU grouping
    }

    const groupedLineItems = groupLineItems(MOCK_LICENSE_SKU_USAGE_WITH_COST_CENTER_USAGE, UsageGrouping.SKU)

    if (groupedLineItems.length === 0 || !groupedLineItems[0]) {
      throw new Error('groupedLineItems is empty or invalid')
    }

    const updatedItem = applyLicenseQuantities(
      groupedLineItems[0] as ProductUsageLineItem,
      MOCK_LICENSE_SKU_USAGE_WITH_COST_CENTER_USAGE,
      filters,
    )
    expect(updatedItem.dailyLicenseQuantity).toBeCloseTo(4, 5) // Compare up to 5 decimal places
    expect(updatedItem.dailyLicenseCost).toBeCloseTo(3.9, 5) // Compare up to 5 decimal places
  })

  it('should return the original item if SKU is not licensed', () => {
    const filters = DEFAULT_FILTERS

    const updatedItem = applyLicenseQuantities(PRODUCT_USAGE_LINE_ITEM, [PRODUCT_USAGE_LINE_ITEM], filters)

    expect(updatedItem).toEqual(PRODUCT_USAGE_LINE_ITEM)
    expect(updatedItem.dailyLicenseQuantity).toBeUndefined()
    expect(updatedItem.dailyLicenseCost).toBeUndefined()
  })

  it('should skip license calculations for periods other than this month or last month', () => {
    const filters = {
      ...DEFAULT_FILTERS,
      period: {type: UsagePeriod.THIS_YEAR, displayText: 'This Year'},
    }

    const groupedLineItems = groupLineItems(MOCK_LICENSE_SKU_USAGE_WITH_COST_CENTER_USAGE, UsageGrouping.SKU)

    if (groupedLineItems.length === 0 || !groupedLineItems[0]) {
      throw new Error('groupedLineItems is empty or invalid')
    }

    const lineItem = groupedLineItems[0] as ProductUsageLineItem
    // Create a test item with some dailyLicenseQuantity and dailyLicenseCost values
    const testItem = {
      ...lineItem,
      dailyLicenseQuantity: 5,
      dailyLicenseCost: 2,
    }

    const updatedItem = applyLicenseQuantities(testItem, MOCK_LICENSE_SKU_USAGE_WITH_COST_CENTER_USAGE, filters)

    // Should return the original item unchanged since the period is THIS_YEAR
    expect(updatedItem).toEqual(testItem)
    expect(updatedItem.dailyLicenseQuantity).toBe(5)
    expect(updatedItem.dailyLicenseCost).toBe(2)
  })
})
