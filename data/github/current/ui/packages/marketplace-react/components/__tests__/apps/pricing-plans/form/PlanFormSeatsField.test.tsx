import {screen} from '@testing-library/react'
import {renderInPlanForm} from '../../../../../test-utils/RenderPlanForm'
import PlanFormSeatsField from '../../../../apps/pricing-plans/form/PlanFormSeatsField'

describe('PlanFormSeatsField', () => {
  test('does not render if plan is free', () => {
    renderInPlanForm(<PlanFormSeatsField />, {
      plan: {isPaid: false},
    })

    expect(screen.queryByTestId('plan-form-price')).not.toBeInTheDocument()
  })

  describe('when the plan is paid per unit', () => {
    test('renders the seat quantity field', () => {
      renderInPlanForm(<PlanFormSeatsField />, {
        plan: {isPaid: true, perUnit: true},
      })

      expect(screen.getByTestId('seat-quantity-input')).toBeInTheDocument()
    })

    test('renders pricing per seat information', () => {
      renderInPlanForm(<PlanFormSeatsField />, {
        plan: {isPaid: true, perUnit: true, price: '$5', unitName: 'seat'},
        planInfo: {isUserBilledMonthly: true},
      })

      expect(screen.getByText('$5')).toBeInTheDocument()
      expect(screen.getByText('/ seat')).toBeInTheDocument()
      expect(screen.getByText('/ month')).toBeInTheDocument()
    })
  })

  describe('when the plan is not paid per unit', () => {
    test('does not render the seat quantity field', () => {
      renderInPlanForm(<PlanFormSeatsField />, {
        plan: {isPaid: true, perUnit: false},
      })

      expect(screen.queryByTestId('seat-quantity-input')).not.toBeInTheDocument()
    })

    test('renders pricing information without per seat information', () => {
      renderInPlanForm(<PlanFormSeatsField />, {
        plan: {isPaid: true, perUnit: false, price: '$5', unitName: 'seat'},
        planInfo: {isUserBilledMonthly: true},
      })

      expect(screen.getByText('$5')).toBeInTheDocument()
      expect(screen.getByText('/ month')).toBeInTheDocument()
      expect(screen.queryByText('/ seat')).not.toBeInTheDocument()
    })
  })
})
