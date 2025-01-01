import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import InputLabel from '@github-ui/input-label'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import {
  RepositoryFragment,
  RepositoryPickerInternal,
  TopRepositoriesFragment,
} from '@github-ui/item-picker/RepositoryPicker'
import type {
  RepositoryPickerRepository$data,
  RepositoryPickerRepository$key,
} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {RepositoryPickerTopRepositories$key} from '@github-ui/item-picker/RepositoryPickerTopRepositories.graphql'
import type {RepositoryPickerTopRepositoriesQuery$data} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {readInlineData, useFragment} from 'react-relay'

import type {DraftIssue} from '../content-preview-types'
import styles from './RepositoryPicker.module.css'
import {useDraftIssueRepository} from './use-draft-issue-repository'

type RepositoryPickerProps = {
  draftIssue: DraftIssue
  resolvedDraftIssueRepo: RepositoryPickerRepository$data | null | undefined
  loadingDraftIssueRepo: boolean
  topReposQuery?: RepositoryPickerTopRepositoriesQuery$data
}

export function RepositoryPicker({
  draftIssue,
  resolvedDraftIssueRepo,
  loadingDraftIssueRepo,
  topReposQuery,
}: RepositoryPickerProps) {
  const [key, setKey] = useState<string | undefined>(undefined)
  const {repository: formRepository, setRepository: setFormRepository} = useIssueCreateDataContext()
  const topReposData = useFragment<RepositoryPickerTopRepositories$key>(TopRepositoriesFragment, topReposQuery?.viewer)

  const topRepos = useMemo(() => {
    if (topReposData == null) {
      return undefined
    }
    return (topReposData?.topRepositories.edges || []).flatMap(a =>
      // eslint-disable-next-line no-restricted-syntax
      a?.node ? [readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, a.node)] : [],
    )
  }, [topReposData])

  const onSelect = useCallback(
    (newSelectedRepo: RepositoryPickerRepository$data | undefined) => {
      // Disallow deselection
      if (newSelectedRepo != null) {
        setFormRepository(newSelectedRepo)
      }
    },
    [setFormRepository],
  )

  useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos)

  // Side effect to ensure RepositoryPickerInternal to memorize the selected non-top-repositories repo.
  useEffect(() => {
    if (
      !loadingDraftIssueRepo &&
      formRepository != null &&
      topRepos != null &&
      !topRepos.find(node => node.id === formRepository.id)
    ) {
      setKey(formRepository.id)
    }
  }, [formRepository, loadingDraftIssueRepo, topRepos])

  const {ssoOrganizations} = useChatState()
  const ssoOrgNames = useMemo(() => ssoOrganizations?.map(org => org.login) ?? [], [ssoOrganizations])

  if (!loadingDraftIssueRepo && formRepository == null && (topRepos == null || topRepos.length === 0)) {
    return null
  }

  // A UX only step to force a default repository from the top repositories list instead of letting
  // the RepositoryPickerInternal to do so since it only does this once after the first render.
  const selectedRepo = formRepository ?? topRepos?.[0]
  // Prevents user change when:
  // 1. Waiting for streaming
  // 1. Waiting for resolving draft issue repo
  // 2. Draft issue repo is not set yet (which should eventually happen)
  const readonly = draftIssue.isStreaming || loadingDraftIssueRepo || resolvedDraftIssueRepo == null

  return (
    <div className={styles.container}>
      <InputLabel className={clsx(styles.label, 'sr-only')} required>
        Repository
      </InputLabel>
      <RepositoryPickerInternal
        key={key}
        initialRepository={selectedRepo}
        onSelect={onSelect}
        options={{hasIssuesEnabled: true, readonly}}
        topRepositoriesData={topReposQuery ? topReposQuery.viewer : null}
        enforceAtleastOneSelected
        subtitle={
          <SingleSignOnBanner
            className={styles.ssoBanner}
            forceWrap
            protectedOrgs={ssoOrgNames}
            maxVisibleOrgNames={0}
            redirectURI={() => `/search/refresh_blackbird_caches?return_to=${location.href}`}
          />
        }
      />
    </div>
  )
}
