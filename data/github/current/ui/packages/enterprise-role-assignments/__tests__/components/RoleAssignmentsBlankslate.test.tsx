import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RoleAssignmentsBlankslate} from '../../components/RoleAssignmentsBlankslate'
import {RoutingProvider} from '@github-ui/role-assignments/routing-provider'

const defaultProps = {
  roleType: 'enterprise',
  actorTypePlural: 'users',
  hasWriteAccess: true,
}

const RoutingProviderWrapper = ({children}: {children: React.ReactNode}) => (
  <RoutingProvider slug="slug" ownerType="enterprise">
    {children}
  </RoutingProvider>
)

test('Renders RoleAssignmentBlankslate', () => {
  render(<RoleAssignmentsBlankslate {...defaultProps} />, {wrapper: RoutingProviderWrapper})

  expect(screen.getByText('No enterprise roles assigned')).toBeInTheDocument()
  expect(screen.getByText('Enterprise roles have not been assigned to any users.')).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Assign role'})).toBeInTheDocument()
})

test('renders the primary action when usePrimaryAction is true', () => {
  render(<RoleAssignmentsBlankslate {...defaultProps} usePrimaryAction />, {wrapper: RoutingProviderWrapper})

  expect(screen.getByRole('link', {name: 'Assign role'})).toHaveAttribute('data-variant', 'primary')
})

test('renders the secondary action when usePrimaryAction is false', () => {
  render(<RoleAssignmentsBlankslate {...defaultProps} usePrimaryAction={false} />, {wrapper: RoutingProviderWrapper})

  expect(screen.getByRole('link', {name: 'Assign role'})).not.toHaveAttribute('data-variant')
})

test('does not display any action when hasWriteAccess is false', () => {
  render(<RoleAssignmentsBlankslate {...defaultProps} hasWriteAccess={false} />, {wrapper: RoutingProviderWrapper})

  expect(screen.queryByRole('link', {name: 'Assign role'})).not.toBeInTheDocument()
})
