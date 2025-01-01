import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import {useEffect, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useOnChangeCallback} from './use-on-change-callback'
import {type Project, useProjectsQuery} from './use-projects-query'

export function useDraftIssueProjects(draftIssue: DraftIssue) {
  const {repository, projects: formProjects, setProjects: setFormProjects} = useIssueCreateDataContext()
  const [lastKnownFormProjects, setLastKnownFormProjects] = useState<Project[]>(formProjects)

  const {isLoading: loadingResolvedProjects, data: resolvedProjects} = useProjectsQuery({
    owner: repository?.owner.login,
    repo: repository?.name,
    projects: draftIssue.projects,
  })

  const onChange = useOnChangeCallback({
    ...draftIssue,
    projects: resolvedProjects?.map(a => a.title) ?? [],
  })

  useEffect(() => {
    if (!loadingResolvedProjects && resolvedProjects) {
      if (repository?.viewerIssueCreationPermissions?.triageable) {
        setFormProjects(resolvedProjects)
      } else if (repository != null) {
        // When switching repositories, the user may not have necessary perms for the new repo,
        // but if they did for the previous repo, there could be data stored in the browser session.
        // In this case, remove the values (which will update that session data).
        setFormProjects([])
      }
    }
  }, [
    loadingResolvedProjects,
    resolvedProjects,
    setFormProjects,
    repository?.viewerIssueCreationPermissions?.triageable,
    repository,
  ])

  useEffect(() => {
    // Keep track of changes _only_ to the projects, between what was passed to the form
    // and what was changed in the project dropdown.
    // This in turn can cause initProjects and contextProjects to change, also causing this to fire
    // In that case the difference calculation is handled in useOnChangeCallback above, and we only store new version
    // if there's a material difference (in case of version switches we won't have a difference)
    if (!loadingResolvedProjects && lastKnownFormProjects !== formProjects) {
      onChange({projects: formProjects.map(a => a.title)})
      setLastKnownFormProjects(formProjects)
    }
  }, [loadingResolvedProjects, lastKnownFormProjects, formProjects, onChange])
}
