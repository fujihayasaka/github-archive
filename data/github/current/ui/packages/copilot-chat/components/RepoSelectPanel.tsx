import {sendEvent} from '@github-ui/hydro-analytics'
import type {RepositoryPickerTopRepositories$key} from '@github-ui/item-picker/RepositoryPickerTopRepositories.graphql'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {testIdProps} from '@github-ui/test-id-props'
import {ActionList} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {type RefObject, useCallback, useEffect, useMemo, useState} from 'react'
import {flushSync} from 'react-dom'

import {useRepositoryItems} from '../hooks/use-repository-items'
import {group} from '../utils/array'
import {makeRepositoryReference} from '../utils/copilot-chat-helpers'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {COPILOT_CHAT_TOPIC_PICKER_PORTAL_ROOT, TopicPickerPortalContainer} from './PortalContainerUtils'
import {RepositoryListItem} from './RepositoryListItem'

type RepoTopicSelectPanelProps = Omit<
  RepoSelectPanelProps,
  'selectedRepoIds' | 'onSelectRepo' | 'selectionVariant' | 'description' | 'error'
>

/** Select only one repo to use as the topic. */
export function RepoTopicSelectPanel(props: RepoTopicSelectPanelProps) {
  const {selectedThreadID, currentTopic} = useChatState()
  const manager = useChatManager()

  const onSelectTopic = useCallback(
    async (repoId: number | string) => {
      copilotLocalStorage.setSelectedTopic(selectedThreadID ?? '', repoId.toString())
      manager.clearCurrentReferences(['image', 'issue'])
      await manager.fetchCurrentRepo(repoId)
    },
    [manager, selectedThreadID],
  )

  return (
    <RepoSelectPanel
      {...props}
      selectionVariant="instant"
      selectedRepoIds={new Set(currentTopic ? [currentTopic.id] : [])}
      onSelectRepo={onSelectTopic}
      description="Choose a repository to chat about."
    />
  )
}

type RepoReferencesSelectPanelProps = RepoTopicSelectPanelProps

/** Select one or more repos to use as references (attachments). */
export function RepoReferencesSelectPanel(props: RepoReferencesSelectPanelProps) {
  const {currentReferences} = useChatState()
  const manager = useChatManager()

  const selectedRepoReferences = currentReferences.filter(r => r.type === 'repository')
  const selectedRepoIds = new Set(selectedRepoReferences.map(r => r.id))

  const [error, setError] = useState<string>()

  const toggleRepoReference = async (repoId: number) => {
    setError(undefined)

    const selectedReference = selectedRepoReferences.find(r => r.id === repoId)
    if (selectedReference) {
      manager.removeReference(selectedReference)
      return
    }

    const repoResponse = await manager.service.fetchRepo(repoId)
    if (!repoResponse.ok) {
      setError('Error: failed to attach repository. Please try again.')
      props.onOpenChange(true)
      return
    }

    const reference = makeRepositoryReference(repoResponse.payload)
    manager.addReference(reference, 'repoMenu')
  }

  return (
    <RepoSelectPanel
      {...props}
      selectionVariant="multiple"
      selectedRepoIds={selectedRepoIds}
      onSelectRepo={toggleRepoReference}
      description="Choose repositories to chat about."
      error={error}
    />
  )
}

interface RepoSelectPanelProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  submitReturnFocusRef: RefObject<HTMLElement>
  cancelReturnFocusRef: RefObject<HTMLElement>
  selectedRepoIds: Set<number>
  /** Repos to feature at the top. Defaults to selected repos. */
  featuredRepoIds?: Set<number>
  onSelectRepo: (repoId: number) => Promise<void>
  selectionVariant: 'instant' | 'multiple'
  description: string
  error?: string
}

export function RepoSelectPanel({
  open,
  onOpenChange,
  submitReturnFocusRef,
  cancelReturnFocusRef,
  selectedRepoIds,
  featuredRepoIds = selectedRepoIds,
  onSelectRepo,
  selectionVariant,
  description,
  error,
}: RepoSelectPanelProps) {
  const {currentRepository, ssoOrganizations} = useChatState()

  const [isFirstTimeLoading, setIsFirstTimeLoading] = useState(true)
  const [filter, setFilter] = useState('')

  useEffect(() => {
    if (!open) setFilter('')
  }, [open])

  const [topRepositoryResults, setTopRepositoryResults] = useState<RepositoryPickerTopRepositories$key | undefined>(
    undefined,
  )

  const {repositories, loading: reposLoading} = useRepositoryItems(
    filter,
    topRepositoryResults,
    setTopRepositoryResults,
    open,
    currentRepository,
  )

  const srRepoSearchStatus = useMemo(() => {
    if (reposLoading) return 'Loading repositories'
    if (repositories.length === 0) return 'No repositories found'
    if (repositories.length === 1) return '1 repository found'
    return `${repositories.length} repositories found`
  }, [reposLoading, repositories.length])

  const onSearchInputChange: React.ChangeEventHandler<HTMLInputElement> = event => {
    setFilter(event.currentTarget.value)
  }

  useEffect(() => {
    if (repositories.length > 0 && isFirstTimeLoading) {
      setIsFirstTimeLoading(false)
    }
  }, [repositories.length, isFirstTimeLoading])

  const ssoOrgNames = useMemo(() => {
    if (!ssoOrganizations) return []
    return ssoOrganizations.map(org => org.login)
  }, [ssoOrganizations])

  // Move features repos to the top
  const {featuredRepos, nonFeaturedRepos} = group(repositories, r =>
    featuredRepoIds.has(r.databaseId) ? 'featuredRepos' : 'nonFeaturedRepos',
  )

  const [selecting, setSelecting] = useState(false)
  const onSelect = async (repoId: number) => {
    setSelecting(true)
    await onSelectRepo(repoId)
    setSelecting(false)
  }

  return (
    <div {...testIdProps('repo-select-panel')}>
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SelectPanel
        width="large"
        maxHeight="xlarge"
        onCancel={() => {
          flushSync(() => onOpenChange(false))
          cancelReturnFocusRef.current?.focus()
          sendEvent('dotcom_chat.activate', {target: 'REPOSITORY_DIALOG_CLOSE', mode: 'immersive'})
        }}
        onSubmit={() => {
          flushSync(() => onOpenChange(false))
          submitReturnFocusRef.current?.focus()
        }}
        open={open}
        variant="modal"
        selectionVariant={selectionVariant}
        title={selectionVariant === 'multiple' ? 'Select repositories' : 'Select a repository'}
        description={description}
      >
        <SelectPanel.Header className={clsx(ssoOrgNames.length > 0 && 'border-bottom-0')}>
          <SelectPanel.SearchInput
            loading={(reposLoading && !isFirstTimeLoading) || selecting}
            onChange={onSearchInputChange}
            placeholder="Search repositories"
            aria-label="Search repositories"
          />
        </SelectPanel.Header>
        <SingleSignOnBanner
          portalContainerName={COPILOT_CHAT_TOPIC_PICKER_PORTAL_ROOT}
          protectedOrgs={ssoOrgNames}
          redirectURI={() => `/search/refresh_blackbird_caches?return_to=${location.href}`}
          isDisplayedInSelectPanel
        />
        <TopicPickerPortalContainer />
        {error && (
          <SelectPanel.Message variant="error" size="inline">
            {error}
          </SelectPanel.Message>
        )}
        <ActionList sx={{minHeight: 340}}>
          <div role="status" className="sr-only">
            {srRepoSearchStatus}
          </div>
          {reposLoading && isFirstTimeLoading ? (
            <SelectPanel.Loading>Fetching repositories&hellip;</SelectPanel.Loading>
          ) : repositories.length === 0 && !reposLoading ? (
            <SelectPanel.Message variant="empty" title="No repositories found">
              Try a different search term
            </SelectPanel.Message>
          ) : (
            <>
              {featuredRepos?.map(repo => (
                <RepositoryListItem
                  key={repo.databaseId}
                  repo={repo}
                  onSelect={onSelect}
                  selected={selectedRepoIds.has(repo.databaseId)}
                />
              ))}
              {featuredRepos && nonFeaturedRepos && <ActionList.Divider />}
              {nonFeaturedRepos?.map(repo => (
                <RepositoryListItem
                  key={repo.databaseId}
                  repo={repo}
                  onSelect={onSelect}
                  selected={selectedRepoIds.has(repo.databaseId)}
                />
              ))}
            </>
          )}
        </ActionList>
      </SelectPanel>
    </div>
  )
}
