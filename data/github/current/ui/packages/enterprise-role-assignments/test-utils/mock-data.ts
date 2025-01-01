// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import type {User} from '@github-ui/react-core/test-utils'
import type {ActorRoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import {act, screen, waitFor} from '@testing-library/react'
import type {Actor, NewRoleAssignmentAssigneeSelectProps} from '../components/NewRoleAssignmentAssigneeSelect'
import type {NewRoleAssignmentListProps} from '../components/NewRoleAssignmentList'
import type {NewRoleAssignmentListItemProps} from '../components/NewRoleAssignmentListItem'
import type {NewRoleAssignmentPageProps} from '../components/NewRoleAssignmentPage'
import type {EnterpriseRoleAssignmentsPayload} from '../routes/EnterpriseRoleAssignments'
import {SelectedTab} from '../types/selected-tab'
import type {NewEnterpriseRoleAssignmentPayload, Role} from '../enterprise-role-assignments-types'

const MAX_ACTORS = 5

const user1: Actor = {
  id: 1,
  name: 'monalisa',
  secondaryName: 'Octocat',
  avatarUrl: 'test.com',
  type: 'user',
}
const team1: Actor = {
  id: 2,
  name: 'team 1',
  secondaryName: null,
  avatarUrl: 'test.com',
  type: 'businessteam',
}
const role1: Role = {
  id: 123,
  name: 'audit_log_readonly',
  description: 'Can read audit logs',
  icon: 'book',
  fgpMetadata: {Enterprise: {category1: ['permissionA']}, Organization: {category2: ['permissionB']}, Repository: {}},
}
const role2: Role = {
  id: 456,
  name: 'manage_members',
  description: 'Can add, remove, promote and demote members',
  icon: 'person',
  fgpMetadata: {Enterprise: {category2: ['permissionB']}, Organization: {}, Repository: {}},
}

export const esmRole: Role = {
  id: 3,
  name: 'Enterprise Security Manager',
  description:
    'Grants the ability to manage security policies, security alerts, and security configurations for an enterprise and all its organizations.',
  icon: 'shield-lock',
  fgpMetadata: {Enterprise: {category: ['security']}, Organization: {}, Repository: {}},
}

export const noFgpsRole: Role = {
  id: 789,
  name: 'empty_role',
  description: 'Im missing permissions',
  icon: 'note',
  fgpMetadata: {Enterprise: {}, Organization: {}, Repository: {}},
}

const roles: Role[] = [role1, role2, noFgpsRole, esmRole]

export const enterpriseOrgs = [
  {id: 100, displayLogin: 'StarWars', avatarURL: 'test.com'},
  {id: 200, displayLogin: 'GOT', avatarURL: 'test2.com'},
]

export function getEnterpriseRoleAssignmentsRoutePayload(
  counts: {
    usersCount: number
    teamsCount: number
  } = {usersCount: 0, teamsCount: 0},
  assignments: ActorRoleAssignment[] = [],
): EnterpriseRoleAssignmentsPayload {
  return {
    slug: 'github-inc',
    ...counts,
    assignments,
    currentPage: 1,
    pageCount: 1,
    hasWriteAccess: true,
    selectedTab: SelectedTab.User,
    canViewEnterpriseTeams: true,
  }
}

export function getNewEnterpriseRoleAssignmentRoutePayload(): NewEnterpriseRoleAssignmentPayload {
  return {
    slug: 'github-inc',
    enterpriseName: 'GitHub Inc',
    enterpriseOrgs,
    enterpriseTeamOrgAssignmentLimitExceeded: false,
    roles,
  }
}

export function getNewRoleAssignmentPageProps(): NewRoleAssignmentPageProps {
  return {
    roles,
    queryActorsPath: '/enterprises/github-inc/enterprise_role_assignment_queries',
    submitAssignmentRoute: '/enterprises/github-inc/enterprise_role_assignments',
    cancelAction: jest.fn(),
  }
}

export function getNewRoleAssignmentAssigneeSelectProps(): NewRoleAssignmentAssigneeSelectProps {
  return {
    assigneeId: null,
    assigneeType: null,
    queryActorsPath: '/enterprises/github-inc/enterprise_role_assignment_queries',
    onSelectCallback: jest.fn(),
  }
}

export function getNewRoleAssignmentListProps(): NewRoleAssignmentListProps {
  return {
    roles,
    assigneeType: null,
    selectedRoleId: null,
    onSelectCallback: jest.fn(),
  }
}

export function getNewRoleAssignmentListItemProps(
  selected: boolean,
  role: Role = role1,
): NewRoleAssignmentListItemProps {
  return {
    role,
    roleStatus: null,
    selected,
    onSelectCallback: jest.fn(),
  }
}

export async function selectAndSubmitRoleAssignment(actingUser: User) {
  const assigneeButton = screen.getByRole('button', {name: 'Select user or team'})
  await actingUser.click(assigneeButton)
  await mockAssigneeQueryResponse([user1], [team1])
  await waitFor(async () => {
    const userItem = screen.getByRole('option', {name: `${user1.name}`})
    await actingUser.click(userItem)

    const roleItem = screen.getByTestId('role-assignment-list-item-audit_log_readonly')
    await actingUser.click(roleItem)

    const submitButton = screen.getByRole('button', {name: 'Assign role'})
    await actingUser.click(submitButton)
  })
}

export async function mockAssigneeQueryResponse(users: Actor[] = [], teams: Actor[] = []) {
  const mockResponse = {
    success: true,
    users: users.slice(0, MAX_ACTORS), // Imitates the server returning a max of 5 users
    teams: teams.slice(0, MAX_ACTORS),
    user_count: users.length,
    team_count: teams.length,
  }

  await act(() =>
    mockFetch.resolvePendingRequest('/enterprises/github-inc/enterprise_role_assignment_queries', mockResponse),
  )
}
