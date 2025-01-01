import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import {useEffect, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {type Label, useLabelsQuery} from './use-labels-query'
import {useOnChangeCallback} from './use-on-change-callback'

export function useDraftIssueLabels(draftIssue: DraftIssue) {
  const {repository, labels: formLabels, setLabels: setFormLabels} = useIssueCreateDataContext()
  const [lastKnownFormLabels, setLastKnownFormLabels] = useState<Label[]>(formLabels)

  const {isLoading: loadingResolvedLabels, data: resolvedLabels} = useLabelsQuery({
    owner: repository?.owner.login,
    repo: repository?.name,
    labels: draftIssue.labels,
  })

  const onChange = useOnChangeCallback({
    ...draftIssue,
    labels: resolvedLabels?.map(a => a.name) ?? [],
  })

  useEffect(() => {
    if (!loadingResolvedLabels && resolvedLabels) {
      if (repository?.viewerIssueCreationPermissions?.labelable) {
        setFormLabels(resolvedLabels)
      } else if (repository != null) {
        // When switching repositories, the user may not have necessary perms for the new repo,
        // but if they did for the previous repo, there could be data stored in the browser session.
        // In this case, remove the values (which will update that session data).
        setFormLabels([])
      }
    }
  }, [
    loadingResolvedLabels,
    resolvedLabels,
    setFormLabels,
    repository?.viewerIssueCreationPermissions?.labelable,
    repository,
  ])

  useEffect(() => {
    if (loadingResolvedLabels || lastKnownFormLabels === formLabels) {
      return
    }

    onChange({labels: formLabels.map(a => a.name)})
    setLastKnownFormLabels(formLabels)
  }, [loadingResolvedLabels, lastKnownFormLabels, formLabels, onChange])
}
