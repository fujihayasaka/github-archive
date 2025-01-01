import {Label} from '@primer/react'
import type {InvoiceLicenseInfo} from '../types/invoice-license-info'
import {format} from 'date-fns'
import {Product} from '../types/product'

type InvoiceRenewalLabelProps = {
  invoiceLicenseInfo: InvoiceLicenseInfo
  product: Product
}

export function InvoiceRenewalLabel({invoiceLicenseInfo, product}: InvoiceRenewalLabelProps) {
  let hasProductRenewal = false
  if (product === Product.GHEC) {
    hasProductRenewal = invoiceLicenseInfo.isGHERenewal || false
  } else if (product === Product.GHAS) {
    hasProductRenewal = invoiceLicenseInfo.isGHASRenewal || false
  }
  const hasFutureProductRenewal = hasProductRenewal && invoiceLicenseInfo.hasFutureRenewal

  if (invoiceLicenseInfo.expired && !hasFutureProductRenewal) {
    return (
      <Label variant="danger" data-testid="invoice-renewal-label">
        Contract expired
      </Label>
    )
  }
  if (hasFutureProductRenewal && invoiceLicenseInfo.renewalScheduledStartDate) {
    return (
      <Label variant="success" data-testid="invoice-renewal-label">
        Renewed from {format(invoiceLicenseInfo.renewalScheduledStartDate, 'MMMM d, yyyy')}
      </Label>
    )
  }
}
