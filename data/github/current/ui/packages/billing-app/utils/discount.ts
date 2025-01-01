import type {DiscountState, Target} from '../types/customer'
import type {EnabledProduct} from '../types/products'
import {DiscountTargetType, DiscountType, DiscountTarget} from '../enums'
import type {DiscountAmount, DiscountAmountsMap, DiscountDataArray} from '../types/discounts'
import {formatMoneyDisplay} from '../utils/money'

import {
  STANDARD_ACTIONS_STORAGE_DISCOUNT_SKUS,
  STANDARD_ACTIONS_MINUTES_DISCOUNT_SKUS,
  STANDARD_LFS_BANDWIDTH_DISCOUNT_SKUS,
  STANDARD_LFS_STORAGE_DISCOUNT_SKUS,
  STANDARD_PACKAGES_BANDWIDTH_DISCOUNT_SKUS,
  STANDARD_PACKAGES_STORAGE_DISCOUNT_SKUS,
  STANDARD_CFB_DISCOUNT_SKUS,
  STANDARD_GHAS_DISCOUNT_SKUS,
  STANDARD_GHEC_DISCOUNT_SKUS,
  PUBLIC_REPO_DISCOUNT_UUID,
  PRODUCT_DISCOUNT_SKU_MAP,
  STANDARD_CODESPACES_STORAGE_DISCOUNT_SKUS,
  STANDARD_CODESPACES_COMPUTE_DISCOUNT_SKUS,
} from '../constants'

// Maps discount target types to a function that returns the text to display in the card
const DISCOUNT_TEXT_MAP: {[key in DiscountTargetType]: string[]} = {
  [DiscountTargetType.ENTERPRISE]: ['Enterprise discount coupon'],
  [DiscountTargetType.ORGANIZATION]: ['Discount for organizations'],
  [DiscountTargetType.REPOSITORY]: ['Discount for repositories'],
  [DiscountTargetType.PUBLIC_REPO]: ['Discount for usage in public repositories'],
  [DiscountTargetType.SKU_ACTIONS_MINUTES]: ['Included Actions minutes'],
  [DiscountTargetType.SKU_ACTIONS_STORAGE]: ['Included Actions storage GBs'],
  [DiscountTargetType.SKU_CFB_SEATS]: ['Included Copilot spending'],
  [DiscountTargetType.SKU_CODESPACES_STORAGE]: ['Included Codespaces storage GBs'],
  [DiscountTargetType.SKU_CODESPACES_COMPUTE]: ['Included Codespaces core hours'],
  [DiscountTargetType.SKU_GHAS_SEATS]: ['Included Advanced Security spending'],
  [DiscountTargetType.SKU_GHEC_SEATS]: ['Included Enterprise spending'],
  [DiscountTargetType.SKU_LFS_BANDWIDTH]: ['Included LFS bandwidth GiBs'],
  [DiscountTargetType.SKU_LFS_STORAGE]: ['Included LFS storage GiBs'],
  [DiscountTargetType.SKU_PACKAGES_BANDWIDTH]: ['Included Packages bandwidth GiBs'],
  [DiscountTargetType.SKU_PACKAGES_STORAGE]: ['Included Packages storage GiBs'],
  [DiscountTargetType.SKU_ACTIONS_PACKAGES_STORAGE_COMBINED]: ['Included Actions and Packages storage GBs'],
  [DiscountTargetType.UNSUPPORTED]: [''],
}

// Maps standard discount SKUs to a single SkuDiscountTargetType for grouping
const SKU_DISCOUNTS_MAP: Record<string, DiscountTargetType> = {}
for (const sku of STANDARD_ACTIONS_MINUTES_DISCOUNT_SKUS)
  SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_ACTIONS_MINUTES
for (const sku of STANDARD_ACTIONS_STORAGE_DISCOUNT_SKUS)
  SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_ACTIONS_STORAGE
for (const sku of STANDARD_CFB_DISCOUNT_SKUS) SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_CFB_SEATS
for (const sku of STANDARD_GHAS_DISCOUNT_SKUS) SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_GHAS_SEATS
for (const sku of STANDARD_GHEC_DISCOUNT_SKUS) SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_GHEC_SEATS
for (const sku of STANDARD_LFS_BANDWIDTH_DISCOUNT_SKUS) SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_LFS_BANDWIDTH
for (const sku of STANDARD_LFS_STORAGE_DISCOUNT_SKUS) SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_LFS_STORAGE
for (const sku of STANDARD_PACKAGES_BANDWIDTH_DISCOUNT_SKUS)
  SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_PACKAGES_BANDWIDTH
for (const sku of STANDARD_PACKAGES_STORAGE_DISCOUNT_SKUS)
  SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_PACKAGES_STORAGE
for (const sku of STANDARD_CODESPACES_STORAGE_DISCOUNT_SKUS)
  SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_CODESPACES_STORAGE
for (const sku of STANDARD_CODESPACES_COMPUTE_DISCOUNT_SKUS)
  SKU_DISCOUNTS_MAP[sku] = DiscountTargetType.SKU_CODESPACES_COMPUTE

export function filterbyEnabledProducts(enabledProducts: EnabledProduct[]): (discount: DiscountState) => boolean {
  return function (discount: DiscountState) {
    const enabled_sku_targets: string[] = []
    for (const product of enabledProducts) {
      enabled_sku_targets.push(...PRODUCT_DISCOUNT_SKU_MAP[product.name])
    }
    for (const target of discount.targets) {
      if (target.type === 'SkuDiscount') {
        if (enabled_sku_targets.includes(target.id)) {
          return true
        } else {
          return false
        }
      } else {
        break
      }
    }
    return true
  }
}

// Maps target amounts to text to display in the card for Actions minutes
const DISCOUNT_TARGET_TEXT_MAP: {[key in DiscountTargetType]?: {[key: number]: string[]}} = {
  [DiscountTargetType.SKU_ACTIONS_MINUTES]: {
    800: ['100,000 included Actions minutes', '(~$800.00 off*)'],
    400: ['50,000 included Actions minutes', '(~$400.00 off*)'],
    24: ['3,000 included Actions minutes', '(~$24.00 off*)'],
    16: ['2,000 included Actions minutes', '(~$16.00 off*)'],
  },
  [DiscountTargetType.SKU_ACTIONS_STORAGE]: {
    0.5: ['2 GB included Actions storage', '(~$0.50 off*)'],
    0.125: ['.5 GB included Actions storage', '(~$0.125 off*)'],
    12.5: ['50 GB included Actions storage', '(~$12.50 off*)'],
    25: ['100 GB included Actions storage', '(~$25.00 off*)'],
  },
  [DiscountTargetType.SKU_LFS_STORAGE]: {
    0.7: ['10 GB included Git LFS storage', '(~$0.70 off*)'],
    17.5: ['250 GB included Git LFS storage', '(~$17.50 off*)'],
  },
  [DiscountTargetType.SKU_LFS_BANDWIDTH]: {
    0.875: ['10 GB included Git LFS bandwidth', '(~$0.875 off*)'],
    21.875: ['250 GB included Git LFS bandwidth', '(~$21.87 off*)'],
  },
  [DiscountTargetType.SKU_PACKAGES_STORAGE]: {
    0.125: ['.5 GB included Packages storage', '(~$0.125 off*)'],
    0.5: ['2 GB included Packages storage', '(~$0.50 off*)'],
    12.5: ['50 GB included Packages storage', '(~$12.00 off*)'],
  },
  [DiscountTargetType.SKU_PACKAGES_BANDWIDTH]: {
    0.5: ['1 GB included Packages data transfer', '(~$0.50 off*)'],
    5: ['10 GB included Packages data transfer', '(~$5.00 off*)'],
    50: ['100 GB included Packages data transfer', '(~$50.00 off*)'],
  },
  [DiscountTargetType.SKU_ACTIONS_PACKAGES_STORAGE_COMBINED]: {
    0.125: ['.5 GB included Actions and Packages storage GBs', '(~$0.125 off*)'],
    0.5: ['2 GB included Actions and Packages storage GBs', '(~$0.50 off*)'],
    12.5: ['50 GB included Actions and Packages storage GBs', '(~$12.00 off*)'],
  },
  [DiscountTargetType.SKU_CODESPACES_STORAGE]: {
    1.05: ['15 GB included Codespaces storage', '(~$1.05 off*)'],
    1.4: ['20 GB included Codespaces storage', '(~$1.40 off*)'],
  },
  [DiscountTargetType.SKU_CODESPACES_COMPUTE]: {
    10.8: ['120 included Codespaces core hours', '(~$10.80 off*)'],
    16.2: ['180 included Codespaces core hours', '(~$16.20 off*)'],
  },
}

export function getTextForDiscount(
  discountAmount: DiscountAmount,
  targetType: DiscountTargetType,
  discountType: DiscountType,
) {
  const {targetAmount} = discountAmount
  let text: string[] | undefined = DISCOUNT_TARGET_TEXT_MAP[targetType]?.[targetAmount]

  // If no product-specific text was found, fall back to the general discount text
  if (!text) {
    text = DISCOUNT_TEXT_MAP[targetType]
    if (discountType === DiscountType.FixedAmount) {
      text[1] = `(${formatMoneyDisplay(targetAmount)} off)`
    }
    if (discountType === DiscountType.Percentage) {
      text[1] = `(${targetAmount}% off)`
    }

    text = [text.join(' ')]
  }

  return text
}

function targetsIncludeBothActionsAndPackagesStorage(targets: Target[]) {
  // return early if there are no targets or if the first target isn't one of the expected targets
  if (targets.length === 0 || (targets[0]?.id !== 'actions_storage' && targets[0]?.id !== 'packages_storage'))
    return false

  let includesActionsStorage = false
  let includesPackagesStorage = false
  for (const target of targets) {
    if (target.id === DiscountTargetType.SKU_ACTIONS_STORAGE) {
      includesActionsStorage = true
    }

    if (target.id === DiscountTargetType.SKU_PACKAGES_STORAGE) {
      includesPackagesStorage = true
    }
  }

  return includesActionsStorage && includesPackagesStorage
}

export function discountTargetToDiscountType(
  targetType: DiscountTarget,
  targetId: string,
  uuid: string,
  targets: Target[],
) {
  // Check for the combined actions/packages storage discount type
  if (targetType === DiscountTarget.SKU) {
    const areBothActionsAndPackagesStorage = targetsIncludeBothActionsAndPackagesStorage(targets)
    if (areBothActionsAndPackagesStorage) {
      return DiscountTargetType.SKU_ACTIONS_PACKAGES_STORAGE_COMBINED
    }
  }

  switch (targetType) {
    case DiscountTarget.Enterprise:
      return DiscountTargetType.ENTERPRISE
    case DiscountTarget.SKU:
      return SKU_DISCOUNTS_MAP[targetId] ?? DiscountTargetType.UNSUPPORTED
    case DiscountTarget.Organization:
      return DiscountTargetType.ORGANIZATION
    case DiscountTarget.Repository:
      return DiscountTargetType.REPOSITORY
    case DiscountTarget.NoDiscountTarget:
      return uuid === PUBLIC_REPO_DISCOUNT_UUID ? DiscountTargetType.PUBLIC_REPO : DiscountTargetType.UNSUPPORTED
    default:
      return DiscountTargetType.UNSUPPORTED
  }
}

export function getUpdatedDiscountAmounts(data: DiscountDataArray) {
  const updatedDiscountAmounts: DiscountAmountsMap = {}

  for (const discount of data) {
    // The assumption is that all targets are of the same type if there are multiple
    let {id: discountTargetId, type: discountTargetType} = (discount.targets[0] as Target) || {}

    // However for actions and packages storage, they can be combined into a single discount
    const areBothActionsAndPackagesStorageTargets = targetsIncludeBothActionsAndPackagesStorage(discount.targets)
    if (areBothActionsAndPackagesStorageTargets) {
      discountTargetId = DiscountTargetType.SKU_ACTIONS_PACKAGES_STORAGE_COMBINED
      discountTargetType = DiscountTarget.SKU
    }
    const uuid = discount.uuid ?? ''
    const targetType = discountTargetToDiscountType(
      discountTargetType ?? DiscountTarget.NoDiscountTarget,
      discountTargetId ?? '',
      uuid,
      discount.targets,
    )
    if (targetType === DiscountTargetType.UNSUPPORTED) continue

    updatedDiscountAmounts[targetType] ||= {}

    if (discount.percentage !== 0) {
      updatedDiscountAmounts[targetType][DiscountType.Percentage] ||= []
      updatedDiscountAmounts[targetType][DiscountType.Percentage]?.push({
        appliedAmount: discount.currentAmount,
        targetAmount: discount.percentage,
      })
    } else {
      updatedDiscountAmounts[targetType][DiscountType.FixedAmount] ||= {
        appliedAmount: 0,
        targetAmount: 0,
      }
      updatedDiscountAmounts[targetType][DiscountType.FixedAmount]!.appliedAmount += discount.currentAmount
      updatedDiscountAmounts[targetType][DiscountType.FixedAmount]!.targetAmount += discount.targetAmount
    }
  }

  return updatedDiscountAmounts
}
