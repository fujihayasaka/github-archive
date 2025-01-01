import type {RoleFgpsDialogProps} from '../components/RoleFgpsDialog'
import {ActorType} from '../types/ActorRoleAssignment'
import type {FgpMetadata} from '../types/FgpMetadata'

export const role1 = {
  id: 1,
  name: 'Admin',
  description: 'Administrator role',
  octicon: 'book',
}

export const role2 = {
  id: 2,
  name: 'Viewer',
  description: 'Viewer role',
  octicon: 'note',
}

export const directRoleAssignment = {
  role: role1,
  directly_assigned: true,
  indirect_assignments: [],
}

export const indirectRoleAssignment = {
  role: role2,
  directly_assigned: false,
  indirect_assignments: [
    {
      team_name: 'Team 1',
      team_url: '/team_1_url',
      type: 'BusinessTeam',
    },
  ],
}

export const mockAssignment = {
  actor: {
    id: 2,
    name: 'Mona Lisa',
    description: 'monalisa',
    avatar_url: '/monalisa.png',
    type: ActorType.User,
  },
  role_assignments: [directRoleAssignment, indirectRoleAssignment],
}

const mockFgpMeta = {
  Enterprise: {category1: ['permissionA']},
  Organization: {category2: ['permissionB']},
  Repository: {},
}

export function getRoleFgpsDialogProps(fgpMetadata: FgpMetadata = mockFgpMeta): RoleFgpsDialogProps {
  return {
    roleId: role1.id,
    title: role1.name,
    subtitle: role1.description,
    fgpMetadata,
    show: true,
    onClose: jest.fn(),
  }
}

const mockActorBasicMeta = {
  id: 1,
  name: 'monalisa team',
  type: ActorType.EnterpriseTeam,
  roleAssignmentsPath: '/test_url',
}

export function getRoleDetailsRowProps() {
  return {
    actor: mockActorBasicMeta,
    role: role1,
    fgpMetadata: mockFgpMeta,
    viewerPermissions: {read: true, write: true},
    canViewEnterpriseTeams: true,
  }
}

export function getRoleDetailsRowRemoveDialogProps() {
  return {
    actor: mockActorBasicMeta,
    roleId: 2,
    roleName: 'role to remove',
    setOpen: jest.fn(),
    returnFocusRef: undefined,
    canViewEnterpriseTeams: true,
  }
}
