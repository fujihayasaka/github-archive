export interface AzureEmission {
  id: string
  azurePartitionKey: string
  subscriptionId: string
  quantity: number
  GrossQuantity: number
  status: string
  errorMessage: string
  sku: string
  usageEntity: UsageEntity
  estimatedBilledAmount: number
  friendlySkuName: string
}

export interface GetAzureEmissionsRequest {
  month: number
  year: number
}

export interface EmissionDate {
  day: number
  month: number
  year: number
}

export interface UsageEntity {
  usageEntityId: string
  name: string
  isCostCenter: boolean
}

export type Product = {
  friendlyName: string
  productName: string
}

export interface ProductOption extends Product {
  selected: boolean
}
