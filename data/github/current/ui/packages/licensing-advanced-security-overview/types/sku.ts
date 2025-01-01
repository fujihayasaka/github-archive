export interface Sku {
  consumedLicenses: number
  name: string
  purchasedLicenses: number
  sku: string
  unitPrice: number
  billableLicenses: number
  billableAmount: number
  serverOnlyConsumedLicenses: number
  unlimitedLicense: boolean
}
