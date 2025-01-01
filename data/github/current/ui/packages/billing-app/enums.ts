import {
  GROUP_BY_COSTCENTER_TYPE,
  GROUP_BY_NONE_TYPE,
  GROUP_BY_ORG_TYPE,
  GROUP_BY_PRODUCT_TYPE,
  GROUP_BY_REPO_TYPE,
  GROUP_BY_SKU_TYPE,
} from './constants'

export const BillingTarget = {
  NoBillingTarget: 0,
  Zuora: 1,
  Azure: 2,
} as const

export type BillingTarget = (typeof BillingTarget)[keyof typeof BillingTarget]

export const CustomerType = {
  Business: 'Business',
  Organization: 'Organization',
  User: 'User',
} as const

export type CustomerType = (typeof CustomerType)[keyof typeof CustomerType]

export const RequestState = {
  INIT: 'init',
  IDLE: 'idle',
  LOADING: 'loading',
  ERROR: 'error',
} as const

export type RequestState = (typeof RequestState)[keyof typeof RequestState]

export const UsageGrouping = {
  NONE: GROUP_BY_NONE_TYPE,
  ORG: GROUP_BY_ORG_TYPE,
  PRODUCT: GROUP_BY_PRODUCT_TYPE,
  REPO: GROUP_BY_REPO_TYPE,
  SKU: GROUP_BY_SKU_TYPE,
  COSTCENTER: GROUP_BY_COSTCENTER_TYPE,
} as const

export type UsageGrouping = (typeof UsageGrouping)[keyof typeof UsageGrouping]

const THIS_MONTH = 3
export const UsagePeriod = {
  TODAY: 2,
  THIS_MONTH,
  THIS_YEAR: 4,
  LAST_MONTH: 5,
  LAST_YEAR: 6,
  DEFAULT: THIS_MONTH,
} as const

export type UsagePeriod = (typeof UsagePeriod)[keyof typeof UsagePeriod]

export const UsageCardVariant = {
  REPO: 'repo',
  ORG: 'org',
} as const

export type UsageCardVariant = (typeof UsageCardVariant)[keyof typeof UsageCardVariant]

export const DiscountTarget = {
  NoDiscountTarget: 'NoDiscountTarget',
  SKU: 'SkuDiscount',
  Product: 'ProductDiscount',
  Repository: 'RepoDiscount',
  Organization: 'OrgDiscount',
  Enterprise: 'EnterpriseDiscount',
} as const

export type DiscountTarget = (typeof DiscountTarget)[keyof typeof DiscountTarget]

export const DiscountType = {
  NoDiscountType: 'none',
  FixedAmount: 'fixed-amount',
  Percentage: 'percentage',
} as const

export type DiscountType = (typeof DiscountType)[keyof typeof DiscountType]

export const DiscountTargetType = {
  ENTERPRISE: 'enterprise',
  ORGANIZATION: 'org',
  REPOSITORY: 'repo',
  SKU_ACTIONS_MINUTES: 'actions_minutes',
  SKU_ACTIONS_STORAGE: 'actions_storage',
  SKU_CFB_SEATS: 'copilot',
  SKU_GHAS_SEATS: 'ghas_seats',
  SKU_GHEC_SEATS: 'ghec_seats',
  SKU_LFS_BANDWIDTH: 'lfs_bandwidth',
  SKU_LFS_STORAGE: 'lfs_storage',
  SKU_PACKAGES_BANDWIDTH: 'packages_bandwidth',
  SKU_PACKAGES_STORAGE: 'packages_storage',
  PUBLIC_REPO: 'public_repo',
  SKU_ACTIONS_PACKAGES_STORAGE_COMBINED: 'actions_packages_storage_combined',
  SKU_CODESPACES_STORAGE: 'codespaces_storage',
  SKU_CODESPACES_COMPUTE: 'codespaces_compute',
  UNSUPPORTED: 'unsupported',
} as const

export type DiscountTargetType = (typeof DiscountTargetType)[keyof typeof DiscountTargetType]
