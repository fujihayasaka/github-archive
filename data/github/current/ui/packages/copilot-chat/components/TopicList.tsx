import {debounce} from '@github/mini-throttle'
import {addUrlToHistoryStack} from '@github-ui/history'
import {ArrowRightIcon, CircleSlashIcon, SearchIcon} from '@primer/octicons-react'
import {ActionList, Box, Spinner, Text, TextInput} from '@primer/react'
import {useCallback, useMemo, useState} from 'react'

import {useRepositoryItems} from '../hooks/use-repository-items'
import {copilotChatSearchInputId} from '../utils/constants'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {RepositoryListItem} from './RepositoryListItem'

const UNFILTERED_TOPICS_DISPLAY_COUNT = 4

export default function TopicList() {
  const copilotChatManager = useChatManager()
  const {mode, selectedThreadID} = useChatState()

  const [filterText, setFilterText] = useState('')
  // Don't send off new filter queries if the user is typing
  const debouncedSetFilter = debounce((newFilter: string) => setFilterText(newFilter), 400, {start: false})

  const {
    repositories,
    loading: reposLoading,
    resetTopRepoResults,
  } = useRepositoryItems(filterText, true, UNFILTERED_TOPICS_DISPLAY_COUNT)

  const onSelect = useCallback(
    async (repoId: number | string | undefined) => {
      resetTopRepoResults()
      if (repoId === undefined) {
        copilotChatManager.showTopicPicker(false)
        copilotChatManager.clearCurrentTopic()
        copilotChatManager.clearCurrentReferences()
        if (mode === 'immersive') {
          addUrlToHistoryStack(`/copilot`)
        }
        if (selectedThreadID) {
          copilotLocalStorage.setSelectedTopic(selectedThreadID, null)
        }
        return
      } else {
        await copilotChatManager.fetchCurrentRepo(Number(repoId))
        copilotChatManager.showTopicPicker(false)
      }
    },
    [resetTopRepoResults, copilotChatManager, mode, selectedThreadID],
  )

  const srRepoSearchStatus = useMemo(() => {
    if (reposLoading) return 'Loading repositories'
    if (repositories.length === 0) return 'No repositories found'
    if (repositories.length === 1) return '1 repository found'
    return `${repositories.length} repositories found`
  }, [reposLoading, repositories.length])

  return (
    <Box
      sx={{
        border: '1px solid var(--borderColor-default, var(--color-border-default))',
        borderRadius: 2,
        display: 'flex',
        flexDirection: 'column',
        mb: 3,
      }}
    >
      <Box sx={{p: 3, pb: 0}}>
        <TextInput
          id={copilotChatSearchInputId}
          leadingVisual={SearchIcon}
          name="topic-search"
          aria-label="Search repositories to chat about"
          placeholder="Search repositories to chat about"
          onChange={e => debouncedSetFilter(e.target.value)}
          sx={{width: '100%', 'input:placeholder-shown': {textOverflow: 'ellipsis'}}}
        />
      </Box>
      <ActionList>
        <div role="status" className="sr-only">
          {srRepoSearchStatus}
        </div>
        {reposLoading ? (
          // Set the height to be the height of 5 repos to avoid layout shift in successful case (should be most common)
          <Box as="li" sx={{display: 'flex', justifyContent: 'center', py: 2, height: '190px', alignItems: 'center'}}>
            <Spinner />
          </Box>
        ) : repositories.length === 0 ? (
          <ActionList.Item disabled>
            <ActionList.LeadingVisual sx={{color: 'fg.muted'}}>
              <CircleSlashIcon />
            </ActionList.LeadingVisual>
            <Text sx={{color: 'fg.muted'}}>No results found</Text>
          </ActionList.Item>
        ) : (
          <>
            {repositories.length > 0 && (
              <ActionList.Group>
                <ActionList.GroupHeading as="h3">Recent repositories</ActionList.GroupHeading>
                {repositories.map(repo => (
                  <RepositoryListItem
                    key={repo.nwo}
                    repo={repo}
                    onSelect={onSelect}
                    trailingVisualComponent={<ArrowRightIcon />}
                  />
                ))}
              </ActionList.Group>
            )}
          </>
        )}
        <ActionList.Divider sx={{marginInline: 0}} />
        <ActionList.Item
          key="chat-with-no-context"
          id="chat-with-no-context"
          onSelect={() => onSelect(undefined)}
          sx={{'#chat-with-no-context--label': {marginBottom: '0px !important'}}}
        >
          General purpose chat
          <ActionList.TrailingVisual>
            <ArrowRightIcon />
          </ActionList.TrailingVisual>
        </ActionList.Item>
      </ActionList>
    </Box>
  )
}
