import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {BusinessTeamRolesView} from '../routes/BusinessTeamRolesView'
import {getBusinessTeamRolesViewRoutePayload, getBusinessTeamRolesViewRoutePayloadEmpty} from '../test-utils/mock-data'

test('Renders header w/ roles tab current', () => {
  const routePayload = getBusinessTeamRolesViewRoutePayload()
  render(<BusinessTeamRolesView />, {
    routePayload,
  })

  // assert any content from header
  expect(screen.getByTestId('overview-team-name')).toBeInTheDocument()

  const rolesTab = screen.getByTestId('nav-Assigned roles')
  expect(rolesTab).toHaveAttribute('aria-current', 'page')

  const orgsTab = screen.getByTestId('nav-Organizations')
  expect(orgsTab).toBeInTheDocument()
})

test('Renders header without Organizations tab when org assignments is disabled', () => {
  const routePayload = getBusinessTeamRolesViewRoutePayload()
  routePayload.orgAssignmentsEnabled = false

  render(<BusinessTeamRolesView />, {
    routePayload,
  })

  const orgsTab = screen.queryByTestId('nav-Organizations')
  expect(orgsTab).not.toBeInTheDocument()
})

test('Renders blank slate when no roles', () => {
  const routePayload = getBusinessTeamRolesViewRoutePayloadEmpty()
  render(<BusinessTeamRolesView />, {
    routePayload,
  })

  expect(screen.getByText('You have no assigned roles')).toBeInTheDocument()
  expect(screen.getByText('You can assign multiple enterprise roles to your team.')).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Assign Enterprise role'})).toBeInTheDocument()
})

test('Renders table when there are roles', () => {
  const routePayload = getBusinessTeamRolesViewRoutePayload()
  render(<BusinessTeamRolesView />, {
    routePayload,
  })

  // table header
  expect(screen.getByText('Enterprise roles')).toBeInTheDocument()
  const assignButton = screen.getByRole('link', {name: 'Assign Enterprise role'})
  expect(assignButton).toBeInTheDocument()
  expect(assignButton).toHaveAttribute('href', '/enterprises/acme-corp/enterprise_role_assignments/new')
  // rows for each roles in payload
  expect(screen.getByText('admin role title')).toBeInTheDocument()
  expect(screen.getByText('admin role description')).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Actions for admin role title'})).toBeInTheDocument()
  expect(screen.getByText('manager role title')).toBeInTheDocument()
  expect(screen.getByText('manager role description')).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Actions for manager role title'})).toBeInTheDocument()
})
