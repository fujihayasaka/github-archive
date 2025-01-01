import {render, screen} from '@testing-library/react'
import {getInvoiceLicenseInfo} from '../../test-utils/mock-data'
import {Product} from '../../types/product'
import {InvoiceRenewalButton} from '../InvoiceRenewalButton'
import {NavigationContextProvider} from '../../contexts/NavigationContext'

const defaultProps = {
  invoiceLicenseInfo: getInvoiceLicenseInfo(),
  product: Product.GHEC,
}

const renderInvoiceRenewalButton = (overrideProps = {}) => {
  return render(
    <NavigationContextProvider enterpriseContactUrl="" isStafftools={false} slug={'test-co'}>
      <InvoiceRenewalButton {...defaultProps} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('InvoiceRenewalButton', () => {
  test('displays "add licenses" when eligible for upgrade', () => {
    renderInvoiceRenewalButton()

    expect(screen.getByRole('link', {name: 'Add licenses'})).toBeInTheDocument()
  })

  test('displays contact sales when there are failed requests', () => {
    renderInvoiceRenewalButton({
      invoiceLicenseInfo: {
        ...defaultProps.invoiceLicenseInfo,
        statusMessage: {
          variant: 'critical',
          text: 'Your Enterprise Cloud seats upgrade failed, please contact sales',
        },
      },
    })

    expect(screen.getByRole('link', {name: 'Contact sales'})).toBeInTheDocument()
  })

  test('displays "renew {product}" when eligible for renewal', () => {
    renderInvoiceRenewalButton({
      invoiceLicenseInfo: {
        ...defaultProps.invoiceLicenseInfo,
        actionType: 'renewal',
      },
      product: Product.GHAS,
    })

    expect(screen.getByRole('link', {name: 'Renew Advanced Security'})).toBeInTheDocument()
  })
})
