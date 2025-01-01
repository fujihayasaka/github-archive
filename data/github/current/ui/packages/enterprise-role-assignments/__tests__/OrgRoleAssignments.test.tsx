import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockAssignment} from '@github-ui/role-assignments/test-utils'
import {ActorType} from '@github-ui/role-assignments/types/actor-role-assignment'
import {OrgRoleAssignments} from '../routes/OrgRoleAssignments'
import {getOrgRoleAssignmentsRoutePayload} from '../test-utils/org-mock-data'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: jest.fn(), showBanner: jest.fn()}
  }),
}))

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

test('Renders the OrgRoleAssignments', () => {
  const routePayload = getOrgRoleAssignmentsRoutePayload()
  render(<OrgRoleAssignments />, {
    routePayload,
  })
  expect(screen.getByRole('heading', {level: 2, name: 'Role assignments'})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Assign role'})).toBeInTheDocument()
})

test('Displays RoleAssignmentBlankslate when there are no users or teams', () => {
  const routePayload = getOrgRoleAssignmentsRoutePayload({usersCount: 0, teamsCount: 0})
  render(<OrgRoleAssignments />, {
    routePayload,
  })

  const blankstate = screen.getByTestId('role-assignments-blankstate')
  expect(blankstate).toBeInTheDocument()
})

test('Displays RoleAssignmentsTable when there are users or teams', () => {
  const routePayload = getOrgRoleAssignmentsRoutePayload({usersCount: 5, teamsCount: 3})
  render(<OrgRoleAssignments />, {
    routePayload,
  })

  expect(screen.getByTestId('role-assignments-table')).toBeInTheDocument()
})

test('Displays Pagination component when page count is greater than 1', () => {
  const routePayload = getOrgRoleAssignmentsRoutePayload({usersCount: 1, teamsCount: 0})
  routePayload.pageCount = 2
  render(<OrgRoleAssignments />, {
    routePayload,
  })

  expect(screen.getByTestId('role-assignment-pagination')).toBeInTheDocument()
})

test('Does not display Pagination component when there is a single page', () => {
  const routePayload = getOrgRoleAssignmentsRoutePayload({usersCount: 1, teamsCount: 0})
  routePayload.pageCount = 1
  render(<OrgRoleAssignments />, {
    routePayload,
  })

  expect(screen.queryByTestId('role-assignment-pagination')).not.toBeInTheDocument()
})

test('Renders enterprise team label for enterprise team assignment', () => {
  const enterpriseTeamAssignment = {
    ...mockAssignment,
    actor: {
      ...mockAssignment.actor,
      type: ActorType.EnterpriseTeam,
    },
  }
  const routePayload = getOrgRoleAssignmentsRoutePayload({usersCount: 0, teamsCount: 1}, [enterpriseTeamAssignment])
  render(<OrgRoleAssignments />, {
    routePayload,
  })

  expect(screen.getByTestId('title-label')).toHaveTextContent('Enterprise team')
})
