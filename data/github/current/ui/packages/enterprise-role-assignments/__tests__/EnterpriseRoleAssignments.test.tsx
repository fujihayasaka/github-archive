import {render} from '@github-ui/react-core/test-utils'
import {mockAssignment} from '@github-ui/role-assignments/test-utils'
import {ActorType} from '@github-ui/role-assignments/types/actor-role-assignment'
import {screen} from '@testing-library/react'
import {EnterpriseRoleAssignments} from '../routes/EnterpriseRoleAssignments'
import {getEnterpriseRoleAssignmentsRoutePayload} from '../test-utils/mock-data'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: jest.fn(), showBanner: jest.fn()}
  }),
}))

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))
const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

afterEach(() => {
  mockIsFeatureEnabled.mockReset()
})

test('Renders the EnterpriseRoleAssignments header', () => {
  mockIsFeatureEnabled.mockReturnValue(true)

  const routePayload = getEnterpriseRoleAssignmentsRoutePayload()
  render(<EnterpriseRoleAssignments />, {routePayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent('Enterprise role assignments')
  expect(screen.queryByRole('navigation')).not.toBeInTheDocument()
})

test('Displays RoleAssignmentBlankslate when there are no users or teams', () => {
  const routePayload = getEnterpriseRoleAssignmentsRoutePayload({usersCount: 0, teamsCount: 0})
  render(<EnterpriseRoleAssignments />, {
    routePayload,
  })

  const blankstate = screen.getByTestId('role-assignments-blankstate')
  expect(blankstate).toBeInTheDocument()
})

test('Displays RoleAssignmentsTable when there are users or teams', () => {
  const routePayload = getEnterpriseRoleAssignmentsRoutePayload({usersCount: 5, teamsCount: 3})
  render(<EnterpriseRoleAssignments />, {
    routePayload,
  })

  expect(screen.getByTestId('role-assignments-table')).toBeInTheDocument()
})

test('Does not render enterprise team label for enterprise team assignment', () => {
  const enterpriseTeamAssignment = {
    ...mockAssignment,
    actor: {
      ...mockAssignment.actor,
      type: ActorType.EnterpriseTeam,
    },
  }
  const routePayload = getEnterpriseRoleAssignmentsRoutePayload({usersCount: 1, teamsCount: 0}, [
    enterpriseTeamAssignment,
  ])
  render(<EnterpriseRoleAssignments />, {
    routePayload,
  })

  expect(screen.queryByTestId('title-label')).not.toBeInTheDocument()
})
