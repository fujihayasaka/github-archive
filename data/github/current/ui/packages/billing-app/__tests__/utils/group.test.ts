import type {ProductUsageLineItem, RepoUsageLineItem, UsageLineItem} from '../../types/usage'
import {UsageGrouping, UsagePeriod} from '../../enums'

import {groupLineItems} from '../../utils/group'

const MOCK_LINE_ITEMS_SAME_DAY_ACTIONS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'actions',
    quantity: 10,
    fullQuantity: 10,
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'Minutes',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'actions',
    quantity: 10,
    fullQuantity: 10,
    sku: 'macos_16_core',
    friendlySkuName: 'Macos 16-core',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'Minutes',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_DIFFERENT_DAY_ACTIONS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'actions',
    quantity: 10,
    fullQuantity: 10,
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'Minutes',
    discountAmount: 1.0,
    totalAmount: 1.59,
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'actions',
    quantity: 10,
    fullQuantity: 10,
    sku: 'macos_16_core',
    friendlySkuName: 'Macos 16-core',
    usageAt: '2023-03-02T10:00:00.00Z',
    unitType: 'Minutes',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_SAME_DAY_STORAGE: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    sku: 'default',
    friendlySkuName: 'Default',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'GigabyteHours',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    sku: 'default',
    friendlySkuName: 'Default',
    usageAt: '2023-03-01T10:00:00.00Z',
    unitType: 'GigabyteHours',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_DIFFERENT_DAY_STORAGE: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    sku: 'default',
    friendlySkuName: 'Default',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'GigabyteHours',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    sku: 'shared_storage',
    friendlySkuName: 'Default',
    usageAt: '2023-03-02T10:00:00.00Z',
    unitType: 'GigabyteHours',
    discountAmount: 0,
    totalAmount: 2.59,
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_SAME_DAY_DIFFERENT_PRODUCTS: UsageLineItem[] = [
  ...MOCK_LINE_ITEMS_SAME_DAY_ACTIONS,
  ...MOCK_LINE_ITEMS_SAME_DAY_STORAGE,
]

const MOCK_LINE_ITEMS_DIFFERENT_DAY_DIFFERENT_PRODUCTS: UsageLineItem[] = [
  ...MOCK_LINE_ITEMS_DIFFERENT_DAY_ACTIONS,
  ...MOCK_LINE_ITEMS_DIFFERENT_DAY_STORAGE,
]

const MOCK_LINE_ITEMS_DIFFERENT_HOUR_STORAGE: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    sku: 'default',
    friendlySkuName: 'Default',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'GigabyteHours',
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    sku: 'default',
    friendlySkuName: 'Default',
    usageAt: '2023-03-01T10:00:00.00Z',
    unitType: 'GigabyteHours',
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_DIFFERENT_REPOS_SAME_ORG: RepoUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T10:00:00.00Z',
    product: 'actions',
    repo: {
      name: 'github',
    },
    org: {
      name: 'github',
      avatarSrc: '',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T10:00:00.00Z',
    product: 'actions',
    repo: {
      name: 'billing-platform',
    },
    org: {
      name: 'github',
      avatarSrc: '',
    },
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_SAME_REPO: RepoUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T10:00:00.00Z',
    product: 'actions',
    repo: {
      name: 'github',
    },
    org: {
      name: 'github',
      avatarSrc: '',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-02T10:00:00.00Z',
    product: 'actions',
    repo: {
      name: 'github',
    },
    org: {
      name: 'github',
      avatarSrc: '',
    },
    name: 'test',
  },
]

const MOCK_LINE_ITEMS_DIFFEERNT_ENTITY_IDS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T10:00:00.00Z',
    product: 'actions',
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    unitType: 'Minutes',
    discountAmount: 1.0,
    totalAmount: 1.59,
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T10:00:00.00Z',
    product: 'actions',
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    unitType: 'Minutes',
    discountAmount: 1.0,
    totalAmount: 1.59,
    name: 'test',
  },
  {
    entityId: 'cost-center1-id',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.5,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T10:00:00.00Z',
    product: 'actions',
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    unitType: 'Minutes',
    discountAmount: 1.0,
    totalAmount: 1.59,
    name: 'test',
  },
]

describe('groupLineItems', () => {
  it('returns an empty array when an empty array of line items is passed', () => {
    expect(groupLineItems([], UsageGrouping.SKU, UsagePeriod.DEFAULT)).toEqual([])
  })

  describe('when group is all', () => {
    it('groups items from the same day into one item', () => {
      expect(groupLineItems(MOCK_LINE_ITEMS_SAME_DAY_ACTIONS, UsageGrouping.NONE, UsagePeriod.DEFAULT)).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5.18,
          discountAmount: 0,
          friendlySkuName: 'Macos 12-core',
          product: 'actions',
          quantity: 20,
          fullQuantity: 20,
          sku: 'macos_12_core',
          totalAmount: 5.18,
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          name: 'test',
        },
      ])
    })

    it('groups items from different days into two items', () => {
      expect(groupLineItems(MOCK_LINE_ITEMS_DIFFERENT_DAY_ACTIONS, UsageGrouping.NONE, UsagePeriod.DEFAULT)).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Macos 12-core',
          product: 'actions',
          quantity: 10,
          fullQuantity: 10,
          sku: 'macos_12_core',
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          discountAmount: 1,
          totalAmount: 1.59,
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Macos 16-core',
          product: 'actions',
          quantity: 10,
          fullQuantity: 10,
          sku: 'macos_16_core',
          usageAt: '2023-03-02T10:00:00.00Z',
          unitType: 'Minutes',
          discountAmount: 0,
          totalAmount: 2.59,
          name: 'test',
        },
      ])
    })

    it('groups items from different products into one', () => {
      expect(
        groupLineItems(MOCK_LINE_ITEMS_DIFFERENT_DAY_DIFFERENT_PRODUCTS, UsageGrouping.NONE, UsagePeriod.DEFAULT),
      ).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5.18,
          friendlySkuName: 'Macos 12-core',
          discountAmount: 1,
          product: 'actions',
          quantity: 20,
          fullQuantity: 20,
          sku: 'macos_12_core',
          totalAmount: 4.18,
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5.18,
          friendlySkuName: 'Macos 16-core',
          discountAmount: 0,
          product: 'actions',
          quantity: 20,
          fullQuantity: 20,
          sku: 'macos_16_core',
          totalAmount: 5.18,
          usageAt: '2023-03-02T10:00:00.00Z',
          unitType: 'Minutes',
          name: 'test',
        },
      ])
    })
  })

  describe('when group is product', () => {
    it('groups items from the same day into products', () => {
      expect(
        groupLineItems(MOCK_LINE_ITEMS_SAME_DAY_DIFFERENT_PRODUCTS, UsageGrouping.PRODUCT, UsagePeriod.DEFAULT),
      ).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5.18,
          discountAmount: 0,
          friendlySkuName: 'Macos 12-core',
          product: 'actions',
          quantity: 20,
          fullQuantity: 20,
          sku: 'macos_12_core',
          totalAmount: 5.18,
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5.18,
          discountAmount: 0,
          friendlySkuName: 'Default',
          product: 'shared_storage',
          quantity: 20,
          fullQuantity: 20,
          sku: 'default',
          totalAmount: 5.18,
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'GigabyteHours',
          name: 'test',
        },
      ])
    })

    it('groups items from the different days into products', () => {
      expect(
        groupLineItems(MOCK_LINE_ITEMS_DIFFERENT_DAY_DIFFERENT_PRODUCTS, UsageGrouping.PRODUCT, UsagePeriod.DEFAULT),
      ).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Macos 12-core',
          product: 'actions',
          quantity: 10,
          fullQuantity: 10,
          sku: 'macos_12_core',
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          discountAmount: 1.0,
          totalAmount: 1.59,
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Macos 16-core',
          product: 'actions',
          quantity: 10,
          fullQuantity: 10,
          sku: 'macos_16_core',
          usageAt: '2023-03-02T10:00:00.00Z',
          unitType: 'Minutes',
          discountAmount: 0,
          totalAmount: 2.59,
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Default',
          product: 'shared_storage',
          quantity: 10,
          fullQuantity: 10,
          sku: 'default',
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'GigabyteHours',
          discountAmount: 0,
          totalAmount: 2.59,
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Default',
          product: 'shared_storage',
          quantity: 10,
          fullQuantity: 10,
          sku: 'shared_storage',
          usageAt: '2023-03-02T10:00:00.00Z',
          unitType: 'GigabyteHours',
          discountAmount: 0,
          totalAmount: 2.59,
          name: 'test',
        },
      ])
    })
  })

  describe('when group is sku', () => {
    it('groups items from different skus from the same day into two items', () => {
      expect(groupLineItems(MOCK_LINE_ITEMS_SAME_DAY_ACTIONS, UsageGrouping.SKU, UsagePeriod.DEFAULT)).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Macos 12-core',
          product: 'actions',
          quantity: 10,
          fullQuantity: 10,
          sku: 'macos_12_core',
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          discountAmount: 0,
          totalAmount: 2.59,
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Macos 16-core',
          product: 'actions',
          quantity: 10,
          fullQuantity: 10,
          sku: 'macos_16_core',
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'Minutes',
          discountAmount: 0,
          totalAmount: 2.59,
          name: 'test',
        },
      ])
    })
  })

  describe('when group is organization', () => {
    it('groups items from different repos under the same organization', () => {
      expect(groupLineItems(MOCK_LINE_ITEMS_DIFFERENT_REPOS_SAME_ORG, UsageGrouping.ORG, UsagePeriod.DEFAULT)).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5,
          discountAmount: undefined,
          product: 'actions',
          org: {
            name: 'github',
            avatarSrc: '',
          },
          quantity: 20,
          fullQuantity: 20,
          repo: {
            name: 'github',
          },
          totalAmount: undefined,
          usageAt: '2023-03-01T10:00:00.00Z',
          name: 'test',
        },
      ])
    })
  })

  describe('when group is repo', () => {
    it('groups items under the same repo from different days', () => {
      expect(groupLineItems(MOCK_LINE_ITEMS_SAME_REPO, UsageGrouping.REPO, UsagePeriod.DEFAULT)).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.5,
          product: 'actions',
          org: {
            name: 'github',
            avatarSrc: '',
          },
          quantity: 10,
          fullQuantity: 10,
          repo: {
            name: 'github',
          },
          usageAt: '2023-03-01T10:00:00.00Z',
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.5,
          product: 'actions',
          org: {
            name: 'github',
            avatarSrc: '',
          },
          quantity: 10,
          fullQuantity: 10,
          repo: {
            name: 'github',
          },
          usageAt: '2023-03-02T10:00:00.00Z',
          name: 'test',
        },
      ])
    })
  })

  describe('when period is today', () => {
    it('groups items from each hour into one when group is all', () => {
      expect(groupLineItems(MOCK_LINE_ITEMS_DIFFERENT_HOUR_STORAGE, UsageGrouping.NONE, UsagePeriod.TODAY)).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Default',
          product: 'shared_storage',
          quantity: 10,
          fullQuantity: 10,
          sku: 'default',
          usageAt: '2023-03-01T08:00:00.00Z',
          unitType: 'GigabyteHours',
          name: 'test',
        },
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.59,
          friendlySkuName: 'Default',
          product: 'shared_storage',
          quantity: 10,
          fullQuantity: 10,
          sku: 'default',
          usageAt: '2023-03-01T10:00:00.00Z',
          unitType: 'GigabyteHours',
          name: 'test',
        },
      ])
    })
  })

  describe('when grouping is by costcenter', () => {
    it('groups items under same usage entity from same day', () => {
      expect(
        groupLineItems(MOCK_LINE_ITEMS_DIFFEERNT_ENTITY_IDS, UsageGrouping.COSTCENTER, UsagePeriod.DEFAULT),
      ).toEqual([
        {
          entityId: '1',
          appliedCostPerQuantity: 0.259,
          billedAmount: 5,
          discountAmount: 2,
          quantity: 20,
          fullQuantity: 20,
          usageAt: '2023-03-01T10:00:00.00Z',
          product: 'actions',
          sku: 'macos_12_core',
          friendlySkuName: 'Macos 12-core',
          totalAmount: 3.18,
          unitType: 'Minutes',
          name: 'test',
        },
        {
          entityId: 'cost-center1-id',
          appliedCostPerQuantity: 0.259,
          billedAmount: 2.5,
          discountAmount: 1,
          quantity: 10,
          fullQuantity: 10,
          usageAt: '2023-03-01T10:00:00.00Z',
          product: 'actions',
          sku: 'macos_12_core',
          friendlySkuName: 'Macos 12-core',
          totalAmount: 1.59,
          unitType: 'Minutes',
          name: 'test',
        },
      ])
    })
  })
})
