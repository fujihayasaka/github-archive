import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {formatMoneyDisplay} from '../../../utils/money'

import NextPaymentCard from '../../../components/payment_due/NextPaymentCard'

import type {NextPaymentCardProps} from '../../../components/payment_due/NextPaymentCard'

const DEFAULT_PROPS: NextPaymentCardProps = {
  nextPaymentDate: 'Oct 10, 2024',
  autoPayDisabled: false,
  hasBill: true,
  meteredViaAzure: false,
  overdue: false,
  latestBillAmount: 100,
  rbiPaymentLink: '/organizations/github/billing/rbi_payment',
  nextChargeAmount: 100,
}

describe('NextPaymentCard', () => {
  test('renders card', () => {
    render(<NextPaymentCard {...DEFAULT_PROPS} />)

    const nextPaymentCard = screen.getByTestId('next-payment-card')
    expect(nextPaymentCard).toBeInTheDocument()
  })

  test('Shows next payment date', () => {
    render(<NextPaymentCard {...DEFAULT_PROPS} />)

    const nextPaymentDate = screen.getByText(DEFAULT_PROPS.nextPaymentDate || 'Oct 10, 2024')
    expect(nextPaymentDate).toBeInTheDocument()
  })

  test('Shows payment history', () => {
    render(<NextPaymentCard {...DEFAULT_PROPS} />)

    const paymentHistoryLink = screen.getByText('Payment history')
    expect(paymentHistoryLink).toBeInTheDocument()
  })

  describe('#autoPayDisabled', () => {
    test('Shows next charge amount', () => {
      render(<NextPaymentCard {...DEFAULT_PROPS} autoPayDisabled />)

      const nextChargeAmount = screen.getByText(`${formatMoneyDisplay(DEFAULT_PROPS.nextChargeAmount)}`)
      expect(nextChargeAmount).toBeInTheDocument()
    })

    test('Shows next payment date when has bill and not overdue', () => {
      render(<NextPaymentCard {...DEFAULT_PROPS} autoPayDisabled />)

      const nextPaymentDate = screen.getByText(`by ${DEFAULT_PROPS.nextPaymentDate}`)
      expect(nextPaymentDate).toBeInTheDocument()
    })

    test('Shows overdue label when overdue', () => {
      render(<NextPaymentCard {...DEFAULT_PROPS} autoPayDisabled overdue />)

      const overdueLabel = screen.getByText('Overdue')
      expect(overdueLabel).toBeInTheDocument()
    })

    test('Hides overdue label when not overdue', () => {
      render(<NextPaymentCard {...DEFAULT_PROPS} autoPayDisabled overdue={false} />)

      const overdueLabel = screen.queryByText('Overdue')
      expect(overdueLabel).toBeNull()
    })

    test('Shows dash when next payment date is null', () => {
      const props = {
        autoPayDisabled: false,
        meteredViaAzure: false,
        nextChargeAmount: 0,
        nextPaymentDate: null,
        overdue: false,
        rbiPaymentLink: '',
        hasBill: false,
        latestBillAmount: 0,
      }
      render(<NextPaymentCard {...props} />)

      const nextPaymentDate = screen.getByTestId('next-payment-date')
      expect(nextPaymentDate).toBeInTheDocument()
      expect(nextPaymentDate).toHaveTextContent('-')
    })
  })

  describe('#meteredViaAzure', () => {
    test('Shows metered billing via azure text', () => {
      render(<NextPaymentCard {...DEFAULT_PROPS} meteredViaAzure />)

      const meteredViaAzure = screen.queryByText('Metered usage billed via Azure is not included.')
      expect(meteredViaAzure).toBeInTheDocument()
    })

    test('Hides metered via Azure copy when meteredViaAzure is false', () => {
      render(<NextPaymentCard {...DEFAULT_PROPS} meteredViaAzure={false} />)

      const meteredViaAzure = screen.queryByText('Metered usage billed via Azure is not included.')
      expect(meteredViaAzure).toBeNull()
    })
  })
})
