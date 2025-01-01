import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {Milestone} from '@github-ui/item-picker/MilestonePicker'
import {useEffect, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useMilestoneQuery} from './use-milestone-query'
import {useOnChangeCallback} from './use-on-change-callback'

function isEqual(left: string | undefined, right: string | undefined) {
  return left?.toLowerCase() === right?.toLowerCase()
}

export function useDraftIssueMilestone(draftIssue: DraftIssue) {
  const {repository, milestone: formMilestone, setMilestone: setFormMilestone} = useIssueCreateDataContext()
  const [lastKnownFormMilestone, setLastKnownFormMilestone] = useState<Milestone | null>(formMilestone)

  const {isLoading: loadingMilestone, data: resolvedMilestone} = useMilestoneQuery({
    owner: repository?.owner.login,
    repo: repository?.name,
    milestone: draftIssue.milestone,
  })

  const onChange = useOnChangeCallback({
    ...draftIssue,
    milestone: resolvedMilestone?.title,
  })

  useEffect(() => {
    if (!loadingMilestone) {
      if (repository?.viewerIssueCreationPermissions?.milestoneable) {
        setFormMilestone(resolvedMilestone ?? null)
      } else if (repository != null) {
        // When switching repositories, the user may not have necessary perms for the new repo,
        // but if they did for the previous repo, there could be data stored in the browser session.
        // In this case, remove the values (which will update that session data).
        setFormMilestone(null)
      }
    }
  }, [
    loadingMilestone,
    resolvedMilestone,
    setFormMilestone,
    repository?.viewerIssueCreationPermissions?.milestoneable,
    repository,
  ])

  useEffect(() => {
    // Keep track of changes _only_ to the milestone, between what was passed to the form
    // and what was changed in the milestone dropdown.
    // This in turn can cause initMilestone and contextMilestone to change, also causing this to fire.
    // In that case, the difference calculation is handled in useOnChangeCallback above, and we only store the new version
    // if there's a material difference (in case of version switches, we won't have a difference).
    if (!loadingMilestone && !isEqual(lastKnownFormMilestone?.title, formMilestone?.title)) {
      onChange({milestone: formMilestone?.title})
      setLastKnownFormMilestone(formMilestone)
    }
  }, [loadingMilestone, lastKnownFormMilestone, formMilestone, onChange])
}
