import {
  PlayIcon,
  type Icon,
  CopilotIcon,
  GlobeIcon,
  ShieldCheckIcon,
  DatabaseIcon,
  PackageIcon,
  CodespacesIcon,
} from '@primer/octicons-react'

export const Products = {
  actions: 'actions',
  copilot: 'copilot',
  git_lfs: 'git_lfs',
  ghec: 'ghec',
  ghas: 'ghas',
  packages: 'packages',
  codespaces: 'codespaces',
} as const

export type Products = (typeof Products)[keyof typeof Products]

// TODO: Remove this once we have a way to get the meter type from the enabled products API
export const MeteredProducts = {
  actions: Products.actions,
  git_lfs: Products.git_lfs,
  packages: Products.packages,
  codespaces: Products.codespaces,
} as const

export type MeteredProducts = (typeof MeteredProducts)[keyof typeof MeteredProducts]

export const SeatBasedProducts = {
  copilot: Products.copilot,
  ghas: Products.ghas,
  ghec: Products.ghec,
} as const

export type SeatBasedProducts = (typeof SeatBasedProducts)[keyof typeof SeatBasedProducts]

export const HighWatermarkProducts = {
  copilot: Products.copilot,
  ghec: Products.ghec,
  ghas: Products.ghas,
} as const

export type HighWatermarkProducts = (typeof HighWatermarkProducts)[keyof typeof HighWatermarkProducts]

// Maps products to their respective usage tab text
export const PRODUCT_TAB_TEXT_MAP: Record<Products, string> = {
  actions: 'Actions',
  copilot: 'Copilot',
  ghas: 'Advanced Security',
  ghec: 'Enterprise',
  git_lfs: 'Git LFS',
  packages: 'Packages',
  codespaces: 'Codespaces',
}

// Maps products to their respective usage tab icon
export const PRODUCT_TAB_ICON_MAP: Record<Products, Icon> = {
  actions: PlayIcon,
  copilot: CopilotIcon,
  ghas: ShieldCheckIcon,
  ghec: GlobeIcon,
  git_lfs: DatabaseIcon,
  packages: PackageIcon,
  codespaces: CodespacesIcon,
}

// TODO: All of this should ideally be cleaned up and obtained from the BP API
export const STANDARD_ACTIONS_STORAGE_DISCOUNT_SKUS = ['actions_storage']
export const STANDARD_ACTIONS_MINUTES_DISCOUNT_SKUS = [
  'actions_linux',
  'actions_macos',
  'actions_windows',
  'actions_linux_arm',
  'actions_windows_arm',
]
export const STANDARD_CFB_DISCOUNT_SKUS = ['copilot_for_business']
export const STANDARD_CODESPACES_STORAGE_DISCOUNT_SKUS = ['codespaces_storage']
export const STANDARD_CODESPACES_COMPUTE_DISCOUNT_SKUS = [
  'codespaces_compute_d2',
  'codespaces_compute_d4',
  'codespaces_compute_d8',
  'codespaces_compute_d16',
  'codespaces_compute_d32',
]
export const STANDARD_GHAS_DISCOUNT_SKUS = ['ghas_seats']
export const STANDARD_GHEC_DISCOUNT_SKUS = ['ghec_seats']
export const STANDARD_LFS_BANDWIDTH_DISCOUNT_SKUS = ['git_lfs_bandwidth']
export const STANDARD_LFS_STORAGE_DISCOUNT_SKUS = ['git_lfs_storage']
export const STANDARD_PACKAGES_BANDWIDTH_DISCOUNT_SKUS = ['packages_bandwidth']
export const STANDARD_PACKAGES_STORAGE_DISCOUNT_SKUS = ['packages_storage']
export const COMBINED_ACTIONS_PACKAGES_STORAGE_DISCOUNT_SKUS = ['actions_storage', 'packages_storage']

// Maps products to their respective standard discount SKUs.
// Used to filter discount usage by enabled products in the useDiscounts hook.
export const PRODUCT_DISCOUNT_SKU_MAP: Record<Products, string[]> = {
  actions: [...STANDARD_ACTIONS_MINUTES_DISCOUNT_SKUS, ...STANDARD_ACTIONS_STORAGE_DISCOUNT_SKUS],
  copilot: [...STANDARD_CFB_DISCOUNT_SKUS],
  ghas: [...STANDARD_GHAS_DISCOUNT_SKUS],
  ghec: [...STANDARD_GHEC_DISCOUNT_SKUS],
  git_lfs: [...STANDARD_LFS_BANDWIDTH_DISCOUNT_SKUS, ...STANDARD_LFS_STORAGE_DISCOUNT_SKUS],
  packages: [...STANDARD_PACKAGES_BANDWIDTH_DISCOUNT_SKUS, ...STANDARD_PACKAGES_STORAGE_DISCOUNT_SKUS],
  codespaces: [...STANDARD_CODESPACES_STORAGE_DISCOUNT_SKUS, ...STANDARD_CODESPACES_COMPUTE_DISCOUNT_SKUS],
}

// License-based product costs
// TODO: This should be pulled from the BP API after exposing pricing information in the products API
export const COPILOT_LICENSE_COST = 19.0
export const GHEC_LICENSE_COST = 21.0
export const GHAS_LICENSE_COST = 49.0

export const UNIT_TYPE = [
  'Unknown',
  'Seconds',
  'Minutes',
  'Hours',
  'Bytes',
  'Megabytes',
  'Gigabytes',
  'ByteHours',
  'MegabyteHours',
  'GigabyteMonths',
  'UserMonths',
]
