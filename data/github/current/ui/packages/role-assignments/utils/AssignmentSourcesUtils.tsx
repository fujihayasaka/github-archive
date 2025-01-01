import {Link} from '@primer/react'
import {ActorType, type IndirectRoleAssignmentSource} from '../types/ActorRoleAssignment'

// Create a list of assignment sources for a role
export function getIndirectAssignmentSourceElements(
  roleId: number,
  indirectAssignmentSources: IndirectRoleAssignmentSource[],
  teamSuffix: boolean,
  canViewEnterpriseTeams: boolean,
) {
  const elements = []
  for (const assignment of indirectAssignmentSources) {
    const enterpriseTeamPrefix = assignment.type === ActorType.EnterpriseTeam ? 'enterprise ' : ''
    elements.push(
      <span key={`indirect-${roleId}-${assignment.team_name}`}>
        {canViewAssignmentSource(canViewEnterpriseTeams, assignment) ? (
          <Link inline href={assignment.team_url}>
            {assignment.team_name}
          </Link>
        ) : (
          <span key="direct" className="fgColor-default">
            {assignment.team_name}
          </span>
        )}
        {teamSuffix && <span> {enterpriseTeamPrefix}team</span>}
      </span>,
    )
  }
  return elements
}

// Separate assignments with ', ' and 'and' between the last two. Add oxford comma if there are more than two assignments.
export function createAssignmentSourcesList(elements: JSX.Element[]) {
  return elements.reduce((s: Array<string | JSX.Element>, a, index) => {
    const separator =
      elements.length > 2
        ? index < elements.length - 2
          ? ', '
          : index === elements.length - 2
            ? ', and '
            : ''
        : elements.length === 2 && index === 0
          ? ' and '
          : ''

    s.push(a, separator)
    return s
  }, [])
}

function canViewAssignmentSource(canViewEnterpriseTeams: boolean, assignment: IndirectRoleAssignmentSource) {
  if (assignment.type === ActorType.EnterpriseTeam) return canViewEnterpriseTeams
  return true
}
