import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {IssueType} from '@github-ui/item-picker/IssueTypePicker'
import {useEffect, useMemo, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useIssueTypesQuery} from './use-issue-types-query'
import {useOnChangeCallback} from './use-on-change-callback'

function isEqual(left: string | undefined, right: string | undefined) {
  return left?.toLowerCase() === right?.toLowerCase()
}

export function useDraftIssueType(draftIssue: DraftIssue) {
  const {repository, issueType: formIssueType, setIssueType: setFormIssueType} = useIssueCreateDataContext()
  const [lastKnownFormIssueType, setLastKnownFormIssueType] = useState<IssueType | null>(formIssueType)

  const {isLoading: loadingIssueTypes, data: resolvedIssueTypes} = useIssueTypesQuery({
    owner: repository?.owner.login,
    repo: repository?.name,
  })

  const resolvedIssueType = useMemo(() => {
    if (!draftIssue.issueType) {
      return null
    }
    if (loadingIssueTypes) {
      return null
    }
    return resolvedIssueTypes?.find(t => isEqual(t.name, draftIssue.issueType))
  }, [draftIssue.issueType, loadingIssueTypes, resolvedIssueTypes])

  const onChange = useOnChangeCallback({
    ...draftIssue,
    issueType: resolvedIssueType?.name,
  })

  useEffect(() => {
    if (!loadingIssueTypes) {
      if (repository?.viewerIssueCreationPermissions?.typeable) {
        setFormIssueType(resolvedIssueType ?? null)
      } else if (repository != null) {
        // When switching repositories, the user may not have necessary perms for the new repo,
        // but if they did for the previous repo, there could be data stored in the browser session.
        // In this case, remove the values (which will update that session data).
        setFormIssueType(null)
      }
    }
  }, [
    loadingIssueTypes,
    resolvedIssueType,
    setFormIssueType,
    repository?.viewerIssueCreationPermissions?.typeable,
    repository,
  ])

  useEffect(() => {
    // Keep track of changes _only_ to the issueType, between what was passed to the form
    // and what was changed in the issue type dropdown.
    // This in turn can cause draftIssue.issueType and contextIssueType to change, also causing this to fire
    // In that case the difference calculation is handled in useOnChangeCallback above, and we only store new version
    // if there's a material difference (in case of version switches we won't have a difference)
    if (!loadingIssueTypes && !isEqual(lastKnownFormIssueType?.name, formIssueType?.name)) {
      onChange({issueType: formIssueType?.name})
      setLastKnownFormIssueType(formIssueType)
    }
  }, [loadingIssueTypes, lastKnownFormIssueType, formIssueType, onChange])
}
