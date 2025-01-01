import {render} from '@github-ui/react-core/test-utils'
import {BudgetUserAlertSelector} from '../../components/budget/BudgetUserAlertSelector'
import {PageContext} from '../../App'
import type {EditBudget} from '../../types/budgets'
import {screen} from '@testing-library/react'

const mockSetAlertEnabled = jest.fn()
const mockSetAlertRecipientUserIds = jest.fn()

const defaultProps = {
  alertEnabled: false as EditBudget['alertEnabled'],
  setAlertEnabled: mockSetAlertEnabled,
  setAlertRecipientUserIds: mockSetAlertRecipientUserIds,
  defaultRecipient: ['user1'],
}

const renderComponent = (
  props = {},
  contextValue = {isStafftoolsRoute: false, isEnterpriseRoute: false, isUserRoute: true, isOrganizationRoute: false},
) => {
  const view = render(
    <PageContext.Provider value={contextValue}>
      <BudgetUserAlertSelector {...defaultProps} {...props} />
    </PageContext.Provider>,
  )
  return view
}

describe('BudgetUserAlertSelector', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders correctly', () => {
    renderComponent()
    expect(screen.getByText('Alerts')).toBeInTheDocument()
    expect(
      screen.getByText(
        'Get emails and GitHub notifications when your spending has reached 75%, 90%, and 100% of the budget threshold.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByLabelText('Receive budget threshold alerts')).toBeInTheDocument()
  })

  test('checkbox is checked based on alertEnabled prop', () => {
    renderComponent({alertEnabled: true})
    expect(screen.getByRole('checkbox')).toBeChecked()
  })

  test('checkbox is unchecked based on alertEnabled prop', () => {
    renderComponent({alertEnabled: false})
    expect(screen.getByRole('checkbox')).not.toBeChecked()
  })

  test('toggleReceiveAlerts function works correctly when box is initially unchecked', async () => {
    const {user} = renderComponent({alertEnabled: false})
    const checkbox = screen.getByRole('checkbox')

    await user.click(checkbox)
    expect(mockSetAlertRecipientUserIds).toHaveBeenCalledWith(['user1'])
    expect(mockSetAlertEnabled).toHaveBeenCalledWith(true)
  })

  test('toggleReceiveAlerts function works correctly when box is initially checked', async () => {
    const {user} = renderComponent({alertEnabled: true, defaultRecipient: ['user1']})
    const checkbox = screen.getByRole('checkbox')

    await user.click(checkbox)
    expect(mockSetAlertRecipientUserIds).toHaveBeenCalledWith([])
    expect(mockSetAlertEnabled).toHaveBeenCalledWith(false)
  })

  test('FormControl is disabled when isStafftoolsRoute is true', () => {
    renderComponent(
      {},
      {isStafftoolsRoute: true, isUserRoute: false, isEnterpriseRoute: false, isOrganizationRoute: false},
    )
    expect(screen.getByRole('checkbox')).toBeDisabled()
  })
})
