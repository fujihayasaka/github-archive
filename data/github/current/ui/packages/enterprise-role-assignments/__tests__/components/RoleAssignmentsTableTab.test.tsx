import {render} from '@github-ui/react-core/test-utils'
import {RoleAssignmentsTableTab} from '../../components/RoleAssignmentsTableTab'
import {testIdProps} from '@github-ui/test-id-props'
import {screen} from '@testing-library/react'

test('renders RoleAssignmentsTableTab', () => {
  render(<RoleAssignmentsTableTab title="Users" count={10} to={'/anywhere'} />)

  expect(screen.getByText('Users')).toBeInTheDocument()
  expect(screen.getByText('10')).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute('href', '/anywhere')
})

test('has aria-current=true when isSelected is true', () => {
  const testId = 'role-assignments-table-tab'
  render(<RoleAssignmentsTableTab title="Users" count={10} isSelected to={'/anywhere'} {...testIdProps(testId)} />)

  const filter = screen.getByTestId(testId)
  expect(filter).toHaveAttribute('aria-current', 'true')
})

test('does not have aria-current attribute when isSelected is false', () => {
  const testId = 'role-assignments-table-tab'

  render(<RoleAssignmentsTableTab title="Users" count={10} to={'/anywhere'} {...testIdProps(testId)} />)

  const filter = screen.getByTestId(testId)
  expect(filter).not.toHaveAttribute('aria-current')
})
