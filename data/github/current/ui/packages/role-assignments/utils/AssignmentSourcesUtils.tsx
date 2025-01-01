import {Link} from '@primer/react'
import type {IndirectRoleAssignmentSource} from '../types/ActorRoleAssignment'

// Create a list of assignment sources for a role
export function getIndirectAssignmentSourceElements(
  roleId: number,
  indirectAssignmentSources: IndirectRoleAssignmentSource[],
  teamSuffix: boolean,
) {
  const elements = []
  for (const assignment of indirectAssignmentSources) {
    elements.push(
      <span key={`indirect-${roleId}-${assignment.team_name}`}>
        <Link inline href={assignment.team_url}>
          {assignment.team_name}
        </Link>
        {teamSuffix && <span> team</span>}
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
