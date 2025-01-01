import {RepositoryListItem} from '@github-ui/copilot-chat/components/RepositoryListItem'
import {useRepositoryItems} from '@github-ui/copilot-chat/hooks/use-repository-items'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {RepositoryPickerTopRepositories$key} from '@github-ui/item-picker/RepositoryPickerTopRepositories.graphql'
import {testIdProps} from '@github-ui/test-id-props'
import {ActionList} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {type RefObject, useCallback, useEffect, useMemo, useState} from 'react'
import {flushSync} from 'react-dom'

interface RepoSelectPanelProps {
  open: boolean
  onOpenChange: (value: boolean) => void
  submitReturnFocusRef: RefObject<HTMLElement>
  cancelReturnFocusRef: RefObject<HTMLElement>
}

export function RepoSelectPanel({
  open,
  onOpenChange,
  submitReturnFocusRef,
  cancelReturnFocusRef,
}: RepoSelectPanelProps) {
  const {currentRepository, selectedThreadID} = useChatState()
  const manager = useChatManager()

  const [isFirstTimeLoading, setIsFirstTimeLoading] = useState(true)
  const [filter, setFilter] = useState('')

  useEffect(() => {
    if (!open) setFilter('')
  }, [open])

  const [topRepositoryResults, setTopRepositoryResults] = useState<RepositoryPickerTopRepositories$key | undefined>(
    undefined,
  )

  const onSelect = useCallback(
    async (repoId: number | string) => {
      copilotLocalStorage.setSelectedTopic(selectedThreadID ?? '', repoId.toString())
      manager.clearCurrentReferences()
      await manager.fetchCurrentRepo(repoId)
    },
    [manager, selectedThreadID],
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
        selectionVariant="instant"
        title="Attach a repository"
      >
        <SelectPanel.Header>
          <SelectPanel.SearchInput
            loading={reposLoading && !isFirstTimeLoading}
            onChange={onSearchInputChange}
            placeholder="Search repositories"
          />
        </SelectPanel.Header>
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
            repositories.map(repo => <RepositoryListItem key={repo.nwo} repo={repo} onSelect={onSelect} />)
          )}
        </ActionList>
      </SelectPanel>
    </div>
  )
}
