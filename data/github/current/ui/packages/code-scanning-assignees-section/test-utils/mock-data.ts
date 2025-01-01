import type {CodeScanningAssigneesSectionProps} from '../CodeScanningAssigneesSection'
import type {AssigneesSectionProps} from '../components/AssigneesSection'
import type {Assignee, CodeScanningAssigneesRepository} from '../types'

export function getCodeScanningAssigneesSectionProps(
  data?: Partial<CodeScanningAssigneesSectionProps>,
): CodeScanningAssigneesSectionProps {
  return {
    alertNumber: 123,
    repository: getCodeScanningAssigneesRepository(),
    currentUser: getAssignee(),
    assignees: [getAssignee()],
    readonly: false,
    ...data,
  }
}

export function getAssigneesSectionProps(data?: Partial<AssigneesSectionProps>): AssigneesSectionProps {
  // For now, these have the same shape as CodeScanningAssigneesSectionProps
  return getCodeScanningAssigneesSectionProps(data)
}

export function getCodeScanningAssigneesRepository(
  data?: Partial<CodeScanningAssigneesRepository>,
): CodeScanningAssigneesRepository {
  return {
    ownerLogin: 'monalisa',
    name: 'happy',
    ...data,
  }
}

export function getAssignee(data?: Partial<Assignee>): Assignee {
  return {
    id: 1,
    login: 'monalisa',
    name: 'Mona Lisa',
    avatarUrl: 'https://avatars.githubusercontent.com/ghost?size=40',
    profilePath: '/monalisa',
    isCopilot: false,
    ...data,
  }
}
