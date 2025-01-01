import type {AssigneeType, Role, RoleStatus} from '../enterprise-role-assignments-types'

export function isEsm(role: Role) {
  return role.name === 'Enterprise Security Manager'
}

export function esmStatus(
  assigneeType: AssigneeType | null,
  enterpriseTeamOrgAssignmentLimitExceeded: boolean,
): RoleStatus {
  if (enterpriseTeamOrgAssignmentLimitExceeded) {
    return {
      status: 'disabled',
      statusText: 'Unavailable: Enterprise Teams organization limit exceeded.',
    }
  } else if (assigneeType === 'user') {
    return {
      status: 'disabled',
      statusText: 'Unavailable: includes repository or org-level permissions.',
    }
  }

  return {status: 'enabled'}
}
