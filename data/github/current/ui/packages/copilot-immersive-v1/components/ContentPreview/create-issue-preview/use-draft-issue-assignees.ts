import {copilotSearchLogin, isCopilot} from '@github-ui/assignees/copilot-user'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import {useEffect, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useAssigneesQuery} from './use-assignees-query'
import {useOnChangeCallback} from './use-on-change-callback'

export function useDraftIssueAssignees(draftIssue: DraftIssue) {
  const {repository, assignees: formAssignees, setAssignees: setFormAssignees} = useIssueCreateDataContext()
  const [lastKnownFormAssignees, setLastKnownFormAssignees] = useState<Assignee[]>(formAssignees)

  const {isLoading: loadingResolvedAssignees, data: resolvedAssignees} = useAssigneesQuery({
    owner: repository?.owner.login,
    repo: repository?.name,
    assignees: draftIssue.assignees,
  })

  const onChange = useOnChangeCallback({
    ...draftIssue,
    assignees: resolvedAssignees?.map(a => (isCopilot(a.login) ? copilotSearchLogin : a.login)) ?? [],
  })

  useEffect(() => {
    if (!loadingResolvedAssignees && resolvedAssignees) {
      if (repository?.viewerIssueCreationPermissions?.assignable) {
        setFormAssignees(resolvedAssignees)
      } else if (repository != null) {
        // When switching repositories, the user may not have necessary perms for the new repo,
        // but if they did for the previous repo, there could be data stored in the browser session.
        // In this case, remove the values (which will update that session data).
        setFormAssignees([])
      }
    }
  }, [
    loadingResolvedAssignees,
    resolvedAssignees,
    setFormAssignees,
    repository?.viewerIssueCreationPermissions?.assignable,
    repository,
  ])

  useEffect(() => {
    // Keep track of changes _only_ to the assignees, between what was passed to the form
    // and what was changed in the assignee dropdown.
    // This in turn can cause initAssignees and contextAssignees to change, also causing this to fire
    // In that case the difference calculation is handled in useOnChangeCallback above, and we only store new version
    // if there's a material difference (in case of version switches we won't have a difference)
    if (!loadingResolvedAssignees && lastKnownFormAssignees !== formAssignees) {
      onChange({assignees: formAssignees.map(a => (isCopilot(a.login) ? copilotSearchLogin : a.login))})
      setLastKnownFormAssignees(formAssignees)
    }
  }, [loadingResolvedAssignees, lastKnownFormAssignees, formAssignees, onChange])
}
