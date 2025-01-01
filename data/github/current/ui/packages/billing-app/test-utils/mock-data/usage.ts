import type {
  CustomerSelection,
  NetUsageLineItem,
  OtherUsageLineItem,
  ProductUsageLineItem,
  RepoUsageLineItem,
  UsageChartData,
  UsageLineItem,
  UsageReportSelection,
} from '../../types/usage'
import {UsageGrouping, UsagePeriod} from '../../enums'

import {GITHUB_INC_CUSTOMER} from './customers'

// TODO: Change these to key value pairs so use is more readable
export const CUSTOMER_SELECTIONS: CustomerSelection[] = [
  {id: GITHUB_INC_CUSTOMER.customerId, displayText: 'Metered usage (w/o cost centers)'},
]

export const GROUP_SELECTIONS = [
  {type: UsageGrouping.NONE, displayText: 'None'},
  {type: UsageGrouping.PRODUCT, displayText: 'Product'},
  {type: UsageGrouping.SKU, displayText: 'SKU'},
  {type: UsageGrouping.ORG, displayText: 'Organization'},
  {type: UsageGrouping.REPO, displayText: 'Repository'},
  {type: UsageGrouping.COSTCENTER, displayText: 'Cost Center'},
]

export const PERIOD_SELECTIONS = [
  {type: UsagePeriod.TODAY, displayText: 'Today'},
  {type: UsagePeriod.THIS_MONTH, displayText: 'Current month'},
  {type: UsagePeriod.THIS_YEAR, displayText: 'This year'},
  {type: UsagePeriod.LAST_MONTH, displayText: 'Last month'},
  {type: UsagePeriod.LAST_YEAR, displayText: 'Last year'},
]

export const DEFAULT_FILTERS = {
  customer: CUSTOMER_SELECTIONS[0] as CustomerSelection,
  group: GROUP_SELECTIONS[0],
  period: PERIOD_SELECTIONS[1],
  product: undefined,
  searchQuery: '',
}

export const USAGE_REPORT_SELECTIONS: UsageReportSelection[] = [
  {
    type: 1,
    displayText: 'Current Month',
    dateText: 'January, 2024',
  },
]
export const USAGE_REPORT_SELECTIONS_WITH_LEGACY: UsageReportSelection[] = [
  {
    type: 1,
    displayText: 'Today',
    dateText: '',
  },
  {
    type: 5,
    displayText: 'Legacy usage',
    dateText: '',
  },
]

export const USAGE_REPORT_CUSTOM_RANGE_SELECTIONS: UsageReportSelection[] = [
  ...USAGE_REPORT_SELECTIONS,
  {
    type: 6,
    displayText: 'Custom range',
    dateText: 'Up to 31 days',
  },
]

export const USAGE_LINE_ITEM: UsageLineItem = {
  entityId: '1',
  appliedCostPerQuantity: 0.259,
  billedAmount: 2.59,
  quantity: 10,
  fullQuantity: 10,
  usageAt: '2023-03-01T08:00:00.00Z',
  name: 'test',
}

export const PRODUCT_USAGE_LINE_ITEM: ProductUsageLineItem = {
  entityId: '1',
  appliedCostPerQuantity: 0.259,
  billedAmount: 2.59,
  product: 'actions',
  quantity: 10,
  fullQuantity: 10,
  unitType: 'minutes',
  sku: 'default',
  friendlySkuName: 'Default',
  usageAt: '2023-03-01T08:00:00.00Z',
  name: 'test',
}

export const REPO_USAGE_LINE_ITEM: RepoUsageLineItem = {
  entityId: '1',
  appliedCostPerQuantity: 0.2,
  billedAmount: 10.5,
  discountAmount: 0.0,
  totalAmount: 10.5,
  quantity: 10,
  fullQuantity: 10,
  product: 'actions',
  usageAt: '2023-03-01T08:00:00.00Z',
  org: {
    name: 'test-org-a',
    avatarSrc: 'https://avatars.githubusercontent.com/github',
    login: 'test-org-a',
  },
  repo: {
    name: 'test-repo-a',
  },
  name: 'test',
}

export const REPO_USAGE_LINE_ITEM_WITH_SPACES: RepoUsageLineItem = {
  entityId: '1',
  appliedCostPerQuantity: 0.2,
  billedAmount: 10.5,
  discountAmount: 0.0,
  totalAmount: 10.5,
  quantity: 10,
  fullQuantity: 10,
  product: 'actions',
  usageAt: '2023-03-01T08:00:00.00Z',
  org: {
    name: 'Test Org A',
    avatarSrc: 'https://avatars.githubusercontent.com/github',
    login: 'Test-Org-A',
  },
  repo: {
    name: 'test-repo-a',
  },
  name: 'test',
}

export const MOCK_LINE_ITEMS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    totalAmount: 2.59,
    discountAmount: 0,
    product: 'packages',
    quantity: 10,
    fullQuantity: 10,
    unitType: 'GigabyteHours',
    sku: 'default',
    friendlySkuName: 'Shared Storage',
    usageAt: '2023-03-01T08:00:00.00Z',
    name: 'test',
    dailyLicenseCost: 0,
    dailyLicenseQuantity: 0,
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 3,
    totalAmount: 3,
    discountAmount: 0,
    product: 'actions',
    quantity: 15,
    fullQuantity: 15,
    unitType: 'Minutes',
    sku: 'windows_4_core',
    friendlySkuName: 'Windows 4-core',
    usageAt: '2023-04-02T09:00:00.00Z',
    name: 'test',
    dailyLicenseCost: 0,
    dailyLicenseQuantity: 0,
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.505,
    billedAmount: 10.1,
    totalAmount: 10.1,
    discountAmount: 0,
    product: 'actions',
    quantity: 20,
    fullQuantity: 20,
    unitType: 'Minutes',
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    usageAt: '2023-05-03T10:00:00.00Z',
    name: 'test',
    dailyLicenseCost: 0,
    dailyLicenseQuantity: 0,
  },
]

export const MOCK_LINE_ITEMS_COSTCENTERS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    totalAmount: 2.59,
    discountAmount: 0,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    unitType: 'GigabyteHours',
    sku: 'default',
    friendlySkuName: 'Shared Storage',
    usageAt: '2023-03-01T08:00:00.00Z',
    name: 'test',
    dailyLicenseCost: 0,
    dailyLicenseQuantity: 0,
  },
  {
    entityId: 'cost-center-1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 3,
    totalAmount: 3,
    discountAmount: 0,
    product: 'actions',
    quantity: 15,
    fullQuantity: 15,
    unitType: 'Minutes',
    sku: 'windows_4_core',
    friendlySkuName: 'Windows 4-core',
    usageAt: '2023-04-02T09:00:00.00Z',
    name: 'cost-center-test',
    dailyLicenseCost: 0,
    dailyLicenseQuantity: 0,
  },
  {
    entityId: 'cost-center-1',
    appliedCostPerQuantity: 0.505,
    billedAmount: 10.1,
    totalAmount: 10.1,
    discountAmount: 0,
    product: 'actions',
    quantity: 20,
    fullQuantity: 20,
    unitType: 'Minutes',
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    usageAt: '2023-05-03T10:00:00.00Z',
    name: 'cost-center-test',
    dailyLicenseCost: 0,
    dailyLicenseQuantity: 0,
  },
]

export const MOCK_USAGE_CHART_DATA: UsageChartData[] = [
  {
    data: [
      {
        x: 1722869145,
        y: 0,
        custom: {
          discountAmount: 'N/A',
          grossAmount: 0,
          totalAmount: 'N/A',
        },
      },
      {
        x: 1722869300,
        y: 0,
        custom: {
          discountAmount: 'N/A',
          grossAmount: 0,
          totalAmount: 'N/A',
        },
      },
      {
        x: 1722869500,
        y: 0,
        custom: {
          discountAmount: 'N/A',
          grossAmount: 0,
          totalAmount: 'N/A',
        },
      },
    ],
  },
]

export const MOCK_MERGED_USAGE_LINE_ITEMS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    discountAmount: 0,
    totalAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    unitType: 'GigabyteHours',
    sku: 'default',
    friendlySkuName: 'Shared Storage',
    usageAt: '2023-03-01T08:00:00.00Z',
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 3,
    discountAmount: 0,
    totalAmount: 3,
    product: 'actions',
    quantity: 15,
    fullQuantity: 15,
    unitType: 'Minutes',
    sku: 'windows_4_core',
    friendlySkuName: 'Windows 4-core',
    usageAt: '2023-04-02T09:00:00.00Z',
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.505,
    billedAmount: 10.1,
    discountAmount: 0,
    totalAmount: 10.1,
    product: 'actions',
    quantity: 20,
    fullQuantity: 20,
    unitType: 'Minutes',
    sku: 'macos_12_core',
    friendlySkuName: 'Macos 12-core',
    usageAt: '2023-05-03T10:00:00.00Z',
    name: 'test',
  },
]

export const MOCK_MERGED_USAGE_ROW: ProductUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.259,
    billedAmount: 2.59,
    discountAmount: 0,
    totalAmount: 2.59,
    product: 'shared_storage',
    quantity: 10,
    fullQuantity: 10,
    unitType: 'GigabyteHours',
    sku: 'default',
    friendlySkuName: 'Shared Storage',
    usageAt: '2023-03-01T08:00:00.00Z',
    name: 'test',
  },
]

export const MOCK_REPO_LINE_ITEMS: RepoUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 2,
    discountAmount: 0.0,
    totalAmount: 2.0,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T08:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-a',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-a',
    },
    repo: {
      name: 'test-repo-a',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 1.6,
    discountAmount: 0.0,
    totalAmount: 1.6,
    quantity: 8,
    fullQuantity: 10,
    usageAt: '2023-03-02T08:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-a',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-a',
    },
    repo: {
      name: 'test-repo-a',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 3,
    discountAmount: 0.0,
    totalAmount: 3.0,
    quantity: 15,
    fullQuantity: 15,
    usageAt: '2023-04-02T09:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-b',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-b',
    },
    repo: {
      name: 'test-repo-b',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 3,
    discountAmount: 0.0,
    totalAmount: 3.0,
    quantity: 15,
    fullQuantity: 15,
    usageAt: '2023-04-02T09:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-b',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-b',
    },
    repo: {
      name: 'test-repo-a',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 4,
    discountAmount: 0.0,
    totalAmount: 4.0,
    quantity: 20,
    fullQuantity: 20,
    usageAt: '2023-05-03T10:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-c',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-c',
    },
    repo: {
      name: 'test-repo-c',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 2,
    discountAmount: 0.0,
    totalAmount: 2.0,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T08:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-d',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-d',
    },
    repo: {
      name: 'test-repo-d',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 2,
    discountAmount: 0.0,
    totalAmount: 2.0,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T08:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-e',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-e',
    },
    repo: {
      name: 'test-repo-e',
    },
    name: 'test',
  },
  {
    entityId: '1',
    appliedCostPerQuantity: 0.2,
    billedAmount: 2,
    discountAmount: 0.0,
    totalAmount: 2.0,
    quantity: 10,
    fullQuantity: 10,
    usageAt: '2023-03-01T08:00:00.00Z',
    product: 'actions',
    org: {
      name: 'test-org-f',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'test-org-f',
    },
    repo: {
      name: 'test-repo-f',
    },
    name: 'test',
  },
]

export const MOCK_ORG_LINE_ITEMS: ProductUsageLineItem[] = [
  {
    entityId: '1',
    billedAmount: 2,
    product: 'actions',
    quantity: 10,
    fullQuantity: 10,
    appliedCostPerQuantity: 0.2,
    sku: 'actions_linux',
    friendlySkuName: 'Actions Linux',
    usageAt: '2023-03-01T08:00:00.00Z',
    unitType: 'Minutes',
    name: 'test',
  },
]

export const MOCK_OTHER_USAGE_LINE_ITEMS: OtherUsageLineItem[] = [
  {
    billedAmount: 2,
    netAmount: 2,
    discountAmount: 0,
    usageAt: '2023-03-01T08:00:00.00Z',
  },
  {
    billedAmount: 2,
    netAmount: 2,
    discountAmount: 0,
    usageAt: '2023-03-02T08:00:00.00Z',
  },
]

export const LICENSE_SKU_MOCK_USAGE: NetUsageLineItem[] = [
  {
    entityId: '1',
    appliedCostPerQuantity: 39,
    billedAmount: 6.29032258,
    discountAmount: 0,
    totalAmount: 6.29032258,
    product: 'copilot',
    quantity: 0.161290323,
    fullQuantity: 0.161290323,
    unitType: 'UserMonths',
    sku: 'copilot_enterprise',
    friendlySkuName: 'Copilot Enterprise',
    usageAt: '2025-03-01T08:00:00.00Z',
    name: 'test',
    // this is calculated in billing platform. it equals  appliedCostPerQuantity / days in month of usage
    dailyLicenseCost: 1.25806452,
    // also calculated in billing platform. equals the daily prorated emission * days in month of usage
    dailyLicenseQuantity: 5,
    grossAmount: 6.29032258,
    netAmount: 6.29032258,
  },
]
