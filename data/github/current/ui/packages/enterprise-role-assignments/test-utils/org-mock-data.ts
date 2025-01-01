import {mockFetch} from '@github-ui/mock-fetch'
import type {ActorRoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import {act} from '@testing-library/react'
import type {Role} from '../components/NewRoleAssignmentListItem'
import type {Actor, NewRoleAssignmentAssigneeSelectProps} from '../components/NewRoleAssignmentAssigneeSelect'
import type {NewOrgRoleAssignmentPayload} from '../routes/NewOrgRoleAssignments'
import type {OrgRoleAssignmentsPayload} from '../routes/OrgRoleAssignments'
import {SelectedTab} from '../types/selected-tab'

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
const team2: Actor = {
  id: 3,
  name: 'team 2',
  secondaryName: null,
  avatarUrl: 'test.com',
  type: 'team',
}

export function getOrgRoleAssignmentsRoutePayload(
  counts: {
    usersCount: number
    teamsCount: number
  } = {usersCount: 0, teamsCount: 0},
  assignments: ActorRoleAssignment[] = [],
): OrgRoleAssignmentsPayload {
  return {
    slug: 'github',
    ...counts,
    assignments,
    currentPage: 1,
    pageCount: 1,
    hasWriteAccess: true,
    selectedTab: SelectedTab.User,
  }
}

const role1: Role = {
  id: 123,
  name: 'audit_log_readonly',
  description: 'Can read audit logs',
  icon: 'book',
  fgpMetadata: {Enterprise: {category1: ['permissionA']}, Organization: {category2: ['permissionB']}, Repository: {}},
}
export const enterpriseOwnedOrgRole: Role = {
  id: 456,
  name: 'manage_members',
  description: 'Can add, remove, promote and demote members',
  icon: 'person',
  fgpMetadata: {Enterprise: {}, Organization: {category2: ['permissionB']}, Repository: {}},
  enterpriseOwner: {
    name: 'GitHub, Inc',
    slug: 'github-inc',
  },
}
export const noFgpsRole: Role = {
  id: 789,
  name: 'empty_role',
  description: 'Im missing permissions',
  icon: 'note',
  fgpMetadata: {Enterprise: {}, Organization: {}, Repository: {}},
}
const roles: Role[] = [role1, enterpriseOwnedOrgRole, noFgpsRole]

export function getNewOrgRoleAssignmentRoutePayload(): NewOrgRoleAssignmentPayload {
  return {
    slug: 'github',
    roles,
  }
}

export function getNewOrgRoleAssignmentAssigneeSelectProps(): NewRoleAssignmentAssigneeSelectProps {
  return {
    assigneeId: null,
    assigneeType: null,
    queryActorsPath: '/organizations/github/settings/org_role_assignment_queries',
    onSelectCallback: jest.fn(),
  }
}

export async function mockOrgAssigneeQueryResponse(users: Actor[] = [user1], teams: Actor[] = [team1, team2]) {
  const mockResponse = {success: true, users, teams}
  await act(() =>
    mockFetch.resolvePendingRequest('/organizations/github/settings/org_role_assignment_queries', mockResponse),
  )
}
