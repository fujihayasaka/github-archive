import {Products} from '../../constants'
import type {PricingDetails} from '../../types/pricings'

import type {EnabledProduct} from '../../types/products'

export const MOCK_PRODUCT_ACTIONS = {
  name: Products.actions,
  friendlyProductName: 'Actions',
  zuoraUsageIdentifier: 'fake-identifier-actions',
}

export const MOCK_PRODUCT_COPILOT = {
  name: Products.copilot,
  friendlyProductName: 'Copilot',
  zuoraUsageIdentifier: 'fake-identifier-copilot',
}

export const MOCK_PRODUCT_LFS = {
  name: Products.git_lfs,
  friendlyProductName: 'Git LFS',
  zuoraUsageIdentifier: 'fake-usage-identifier',
}

export const MOCK_PRODUCT_MODELS = {
  name: Products.models,
  friendlyProductName: 'Models',
  zuoraUsageIdentifier: 'fake-identifier-models',
}

// export const MOCK_PRODUCT_SHARED_STORAGE = {
//   name: Products.shared_storage,
//   friendlyProductName: 'LFS',
//   zuoraUsageIdentifier: 'fake-usage-identifier',
// }

export const MOCK_SKUS_PRICING: PricingDetails[] = [
  {
    sku: 'actions_linux',
    friendlyName: 'Actions Linux',
    price: 10,
    meterType: 'Default',
    product: Products.actions,
    azureMeterId: 'azure-meter-actions',
    freeForPublicRepos: true,
    unitType: 'Minutes',
    effectiveAt: 1689366600,
  },
  {
    sku: 'actions_macos',
    friendlyName: 'Actions Macos',
    price: 10,
    meterType: 'Default',
    product: Products.actions,
    azureMeterId: 'azure-meter-actions',
    freeForPublicRepos: true,
    unitType: 'Minutes',
    effectiveAt: 1689366600,
  },
  {
    sku: 'copilot_sku',
    friendlyName: 'Copilot SKU',
    price: 19,
    meterType: 'Default',
    product: Products.copilot,
    azureMeterId: 'azure-meter-copilot',
    freeForPublicRepos: false,
    unitType: 'UserMonths',
    effectiveAt: 1689366600,
  },
  {
    sku: 'lfs_sku',
    friendlyName: 'Git LFS',
    price: 5,
    meterType: 'Default',
    product: Products.git_lfs,
    azureMeterId: 'azure-meter-lfs',
    freeForPublicRepos: false,
    unitType: 'Minutes',
    effectiveAt: 1689366600,
  },
  {
    sku: 'lfs_sku_linux',
    friendlyName: 'Linux',
    price: 5,
    meterType: 'Default',
    product: Products.git_lfs,
    azureMeterId: 'azure-meter-lfs',
    freeForPublicRepos: false,
    unitType: 'Minutes',
    effectiveAt: 1689366600,
  },
  {
    sku: 'models_sku',
    friendlyName: 'Models',
    price: 2,
    meterType: 'Default',
    product: Products.models,
    azureMeterId: 'N/A',
    freeForPublicRepos: false,
    unitType: 'TokenUnits',
    effectiveAt: 1689366600,
  },
]

export const MOCK_PRODUCTS: EnabledProduct[] = [
  MOCK_PRODUCT_ACTIONS,
  MOCK_PRODUCT_COPILOT,
  MOCK_PRODUCT_LFS,
  MOCK_PRODUCT_MODELS,
]

export const initialPricingData: PricingDetails = {
  sku: 'linux_4_core',
  friendlyName: 'Ubuntu 4 Core',
  price: 33,
  meterType: 'Default',
  product: 'actions',
  azureMeterId: 'fake-azure-meter-id',
  freeForPublicRepos: true,
  unitType: 'Minutes',
  effectiveAt: 1689366600,
}
