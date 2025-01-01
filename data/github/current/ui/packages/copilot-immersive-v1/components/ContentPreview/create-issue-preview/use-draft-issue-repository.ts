import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {useEffect, useMemo, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useOnChangeCallback} from './use-on-change-callback'

export function useDraftIssueRepository(
  draftIssue: DraftIssue,
  resolvedDraftIssueRepo: RepositoryPickerRepository$data | null | undefined,
  loadingDraftIssueRepo: boolean,
  topRepos?: RepositoryPickerRepository$data[],
) {
  const {repository: formRepository, setRepository: setFormRepository} = useIssueCreateDataContext()
  const [lastKnownFormRepository, setLastKnownFormRepository] = useState<RepositoryPickerRepository$data | undefined>(
    formRepository,
  )

  const onChange = useOnChangeCallback(draftIssue)
  const skipVersionBump = useMemo(
    () =>
      (!loadingDraftIssueRepo && resolvedDraftIssueRepo?.nameWithOwner == null) ||
      resolvedDraftIssueRepo?.nameWithOwner === formRepository?.nameWithOwner,
    [loadingDraftIssueRepo, resolvedDraftIssueRepo?.nameWithOwner, formRepository?.nameWithOwner],
  )

  useEffect(() => {
    if (draftIssue.isStreaming || loadingDraftIssueRepo) {
      return
    }

    if (resolvedDraftIssueRepo != null) {
      setFormRepository(resolvedDraftIssueRepo)
    } else if (topRepos != null && topRepos.length > 0) {
      setFormRepository(topRepos[0])
    } else {
      setFormRepository(undefined)
    }
  }, [draftIssue.isStreaming, loadingDraftIssueRepo, resolvedDraftIssueRepo, setFormRepository, topRepos])

  useEffect(() => {
    if (lastKnownFormRepository !== formRepository) {
      onChange({repository: formRepository?.nameWithOwner}, skipVersionBump)
      setLastKnownFormRepository(formRepository)
    }
  }, [onChange, formRepository, skipVersionBump, lastKnownFormRepository])
}
