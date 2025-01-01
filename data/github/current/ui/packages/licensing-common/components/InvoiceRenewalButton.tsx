import {Button} from '@primer/react'
import {useNavigation} from '../contexts/NavigationContext'
import type {InvoiceLicenseInfo} from '../types/invoice-license-info'
import type {Product} from '../types/product'

export type InvoiceRenewalButtonProps = {
  invoiceLicenseInfo: InvoiceLicenseInfo
  product: Product
}

export function InvoiceRenewalButton({invoiceLicenseInfo, product}: InvoiceRenewalButtonProps) {
  const {basePath} = useNavigation()
  const invoiceRenewalUrl = `${basePath}/settings/billing/renew`
  const invoiceUpgradeUrl = `${basePath}/settings/billing/add_seats`
  const contactSales = invoiceLicenseInfo.statusMessage?.variant === 'critical'
  const renew = !contactSales && invoiceLicenseInfo.actionType === 'renewal'
  const upgrade = !contactSales && !renew && invoiceLicenseInfo.actionType === 'upgrade'

  if (contactSales) {
    return (
      <Button as="a" href="/renewals-help" variant="default" data-testid="contact-sales-button">
        Contact sales
      </Button>
    )
  }
  if (renew) {
    return (
      <Button as="a" href={invoiceRenewalUrl} variant="default" data-testid="renew-button">
        Renew {product}
      </Button>
    )
  }
  if (upgrade) {
    return (
      <Button as="a" href={invoiceUpgradeUrl} variant="primary" data-testid="upgrade-button">
        Add licenses
      </Button>
    )
  }
  return null
}
