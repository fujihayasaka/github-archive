import {render, screen} from '@testing-library/react'
import {getInvoiceLicenseInfo} from '../../test-utils/mock-data'
import {InvoiceRenewalLabel} from '../InvoiceRenewalLabel'
import {Product} from '../../types/product'
import {format} from 'date-fns'

const defaultProps = {
  invoiceLicenseInfo: getInvoiceLicenseInfo(),
  product: Product.GHEC,
}

const renderInvoiceRenewalLabel = (overrideProps = {}) => {
  return render(<InvoiceRenewalLabel {...defaultProps} {...overrideProps} />)
}

describe('InvoiceRenewalLabel component', () => {
  test('renders contract expired when expired==true', () => {
    renderInvoiceRenewalLabel({
      invoiceLicenseInfo: {
        ...defaultProps.invoiceLicenseInfo,
        expired: true,
      },
    })

    const el = screen.getByTestId('invoice-renewal-label')
    expect(el).toBeInTheDocument()
    expect(el).toHaveTextContent('Contract expired')
  })

  test('renders scheduled renewal date when renewal is in the future', () => {
    const t = '2025-02-03T00:00:00.000Z'
    renderInvoiceRenewalLabel({
      invoiceLicenseInfo: {
        ...defaultProps.invoiceLicenseInfo,
        expired: false,
        hasFutureRenewal: true,
        renewalScheduledStartDate: t,
      },
    })

    const el = screen.getByTestId('invoice-renewal-label')
    expect(el).toBeInTheDocument()
    expect(el).toHaveTextContent(`Renewed from ${format(new Date(t), 'MMMM d, yyyy')}`)
  })

  test('does not render when scheduled renewal date is in the past', () => {
    renderInvoiceRenewalLabel({
      invoiceLicenseInfo: {
        ...defaultProps.invoiceLicenseInfo,
        expired: false,
        hasFutureRenewal: false,
      },
    })

    expect(screen.queryByTestId('invoice-renewal-label')).not.toBeInTheDocument()
  })

  test('does not render when product does not match the invoice renewal info', () => {
    renderInvoiceRenewalLabel({
      product: Product.GHAS,
    })

    expect(screen.queryByTestId('invoice-renewal-label')).not.toBeInTheDocument()
  })
})
