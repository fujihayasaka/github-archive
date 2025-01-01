import {AssigneesSection} from './components/AssigneesSection'
import type {Assignee, CodeScanningAssigneesRepository} from './types'

export interface CodeScanningAssigneesSectionProps {
  alertNumber: number
  repository: CodeScanningAssigneesRepository
  currentUser: Assignee
  assignees: Assignee[]
  readonly: boolean
}

export function CodeScanningAssigneesSection({
  alertNumber,
  repository,
  currentUser,
  assignees,
  readonly,
}: CodeScanningAssigneesSectionProps) {
  return (
    <AssigneesSection
      alertNumber={alertNumber}
      repository={repository}
      currentUser={currentUser}
      assignees={assignees}
      readonly={readonly}
    />
  )
}
