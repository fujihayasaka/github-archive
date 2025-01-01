import {render} from '@github-ui/react-core/test-utils'
import {CancelSubscriptionDialog} from '../CancelSubscriptionDialog'
import {screen} from '@testing-library/react'

const renderCancelSubscriptionDialog = (overrideProps = {}) => {
  const defaultProps = {
    expiration: '2025-03-21T00:00:00.000',
    isCanceling: false,
    onConfirmed: jest.fn(),
    onClose: jest.fn(),
  }
  return render(<CancelSubscriptionDialog {...defaultProps} {...overrideProps} />)
}

describe('CancelSubscriptionDialog Component', () => {
  test('renders the dialog UI elements', () => {
    renderCancelSubscriptionDialog()

    expect(screen.getByRole('heading', {name: 'Cancel GitHub Advanced Security'})).toBeInTheDocument()

    expect(screen.getByRole('dialog')).toBeInTheDocument()

    expect(
      screen.getByText(/your access to GitHub Advanced Security will expire on March 21, 2025/),
    ).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'I understand, cancel Advanced Security'})).not.toBeDisabled()
  })

  test('disables the cancel button when isCanceling is true', () => {
    renderCancelSubscriptionDialog({isCanceling: true})

    expect(screen.getByRole('button', {name: 'Submitting request'})).toBeDisabled()
  })
})
