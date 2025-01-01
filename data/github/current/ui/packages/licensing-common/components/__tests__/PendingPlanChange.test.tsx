import {render, screen, fireEvent} from '@testing-library/react'
import {PendingPlanChange} from '../PendingPlanChange'
import {NavigationContextProvider} from '../../contexts/NavigationContext'
import {getPendingPlanChange} from '../../test-utils/mock-data'
import type {PendingCycleChange} from '../../types/pending-cycle-change'

const defaultProps = {
  onCancelConfirmed: () => {},
  pendingChange: getPendingPlanChange(),
}
interface OverrideProps {
  isStafftools?: boolean
  onCancelConfirmed?: jest.Mock
  pendingChange?: PendingCycleChange
}

const renderPendingPlanChange = (overrideProps: OverrideProps = {}) => {
  return render(
    <NavigationContextProvider
      isTeams={false}
      enterpriseContactUrl={'/enterprise-contact-url'}
      isStafftools={overrideProps.isStafftools ?? false}
      slug={'test-co'}
    >
      <PendingPlanChange {...defaultProps} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('PendingPlanChange Component', () => {
  test('renders pending plan change details correctly', () => {
    renderPendingPlanChange()

    const el = screen.getByTestId('pending-plan-change')
    expect(el).toHaveTextContent('Your change to Premium plan with 5 licenses will be effective on July 1, 2024.')
  })

  test('renders cancellation pending plan change details correctly', () => {
    renderPendingPlanChange({pendingChange: {...defaultProps.pendingChange, isCancellation: true}})

    const el = screen.getByTestId('pending-plan-change')
    expect(el).toHaveTextContent('Your cancellation will be effective on July 1, 2024.')
  })

  test('formats large numbers', () => {
    const pendingChange = getPendingPlanChange()
    pendingChange.newSeatCount = 5000
    renderPendingPlanChange({pendingChange})

    const el = screen.getByTestId('pending-plan-change')
    expect(el).toHaveTextContent('Your change to Premium plan with 5,000 licenses will be effective on July 1, 2024.')
  })

  test('opens cancel confirmation dialog when Cancel button is clicked', () => {
    renderPendingPlanChange()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('cancel-pending-plan-change-button'))

    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  test('cancels pending plan change when OK is clicked in the confirmation dialog', () => {
    const onCancelConfirmed = jest.fn()
    renderPendingPlanChange({onCancelConfirmed})
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('cancel-pending-plan-change-button')) // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('confirm-dialog-confirm-button'))

    expect(onCancelConfirmed).toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  test('dismisses confirmation dialog when Cancel is clicked in the confirmation dialog', () => {
    const onCancelConfirmed = jest.fn()
    renderPendingPlanChange({onCancelConfirmed})
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('cancel-pending-plan-change-button')) // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('confirm-dialog-cancel-button'))

    expect(onCancelConfirmed).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  test('hides Cancel button when isStafftools is set', () => {
    renderPendingPlanChange({isStafftools: true})

    const cancelPendingPlanChangeButton = screen.queryByTestId('cancel-pending-plan-change-button')
    expect(cancelPendingPlanChangeButton).not.toBeInTheDocument()
  })
})
