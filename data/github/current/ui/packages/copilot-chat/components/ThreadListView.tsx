import {AlertIcon, CommentIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, Box, Button, Flash, RelativeTime, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Dialog} from '@primer/react/experimental'
import {type Dispatch, type MutableRefObject, type SetStateAction, useMemo, useRef, useState} from 'react'

import {threadName} from '../utils/copilot-chat-helpers'
import type {CopilotChatManager} from '../utils/copilot-chat-manager'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {CopilotChatThread} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export function ThreadListView() {
  const state = useChatState()
  const manager = useChatManager()
  const threads = useMemo(() => removeSpacesThreads(manager.sortThreads(state.threads)), [state.threads, manager])

  const [shouldShowDeleteAllConfirmation, setShouldShowDeleteAllConfirmation] = useState(false)
  const returnFocusRef = useRef(null)
  const showDeleteAllButton = copilotFeatureFlags.deleteAllConversations

  if (state.threadsLoading.state === 'loading' && threads.length < 2) {
    return (
      <Box
        sx={{
          p: 3,
          height: '100%',
          display: 'grid',
          alignItems: 'center',
          alignContent: 'center',
          flexDirection: 'column',
          justifyItems: 'center',
          gap: 2,
        }}
      >
        <Spinner />
        Loading threads…
      </Box>
    )
  }

  return (
    <>
      {
        // Show an error if there are no threads because we should show the new thread view instead of the list UI
        state.threadsLoading.state === 'error' ? (
          <ErrorView threadsLoading={state.threadsLoading} />
        ) : (
          <>
            {threads.length > 0 && (
              <>
                <ActionList sx={{overflowY: 'auto'}}>
                  <ActionList.Group>
                    <ActionList.GroupHeading as="h3">All conversations</ActionList.GroupHeading>
                    <ListView threads={threads} manager={manager} />
                    {threads.length > 1 && showDeleteAllButton && (
                      <DeleteAll
                        threads={threads}
                        manager={manager}
                        shouldDeleteAllThreads={shouldShowDeleteAllConfirmation}
                        setShouldDeleteAllThreads={setShouldShowDeleteAllConfirmation}
                        returnFocusRef={returnFocusRef}
                      />
                    )}
                  </ActionList.Group>
                </ActionList>
              </>
            )}

            {threads.length === 0 && (
              <Box sx={{p: 3, color: 'fg.subtle'}}>
                <p className="mb-3">There are no conversations at the moment.</p>
                <Button onClick={() => manager.selectThread(null)} block>
                  Start a new conversation
                </Button>
              </Box>
            )}
          </>
        )
      }
    </>
  )
}

const ErrorView = ({threadsLoading}: {threadsLoading: CopilotChatState['threadsLoading']}) => {
  return (
    <Box
      sx={{
        p: 3,
      }}
    >
      <Flash variant="warning">
        <Octicon icon={AlertIcon} />
        {threadsLoading.state === 'error' ? threadsLoading.error : 'Something went wrong. Please try again later.'}
      </Flash>
    </Box>
  )
}

const ListView = ({threads, manager}: {threads: CopilotChatThread[]; manager: CopilotChatManager}) => {
  return (
    <>
      {threads.map(thread => {
        return (
          <ActionList.Item key={thread.id} onSelect={() => manager.selectThread(thread)} className="mr-0 pr-2">
            <ActionList.LeadingVisual>
              <CommentIcon />
            </ActionList.LeadingVisual>
            {threadName(thread)}
            <ActionList.Description variant="inline" className="flex-shrink-0">
              <RelativeTime date={new Date(Date.parse(thread.updatedAt))} format="relative" />
            </ActionList.Description>
            <ActionList.TrailingAction
              icon={TrashIcon}
              label={`Delete conversation: "${threadName(thread)}"`}
              onClick={async () => manager.deleteThreadKeepSelection(thread)}
            />
          </ActionList.Item>
        )
      })}
    </>
  )
}

const DeleteAll = ({
  threads,
  manager,
  shouldDeleteAllThreads,
  setShouldDeleteAllThreads,
  returnFocusRef,
}: {
  threads: CopilotChatThread[]
  manager: CopilotChatManager
  shouldDeleteAllThreads: true | false
  setShouldDeleteAllThreads: Dispatch<SetStateAction<true | false>>
  returnFocusRef: MutableRefObject<null>
}) => {
  return (
    <>
      <Button
        data-testid={`delete-all-threads-button`}
        sx={{mt: 2, ml: 3}}
        ref={returnFocusRef}
        onClick={() => setShouldDeleteAllThreads(true)}
      >
        Delete all conversations
      </Button>
      {shouldDeleteAllThreads === true && (
        <div data-testid={`delete-all-threads-dialog`}>
          <Dialog
            title="Delete all conversations"
            width="small"
            onClose={() => setShouldDeleteAllThreads(false)}
            returnFocusRef={returnFocusRef}
            footerButtons={[
              {
                buttonType: 'default',
                content: 'Cancel',
                onClick: () => setShouldDeleteAllThreads(false),
              },
              {
                buttonType: 'danger',
                content: 'Delete',
                // eslint-disable-next-line @typescript-eslint/no-misused-promises
                onClick: async () => {
                  await manager.deleteAllThreadKeepSelection(threads)
                  setShouldDeleteAllThreads(false)
                },
                autoFocus: true,
              },
            ]}
          >
            You are trying to delete {threads.length} conversations. Are you sure? This can’t be undone.
          </Dialog>
        </div>
      )}
    </>
  )
}

// Remove threads that started from Copilot Spaces
const removeSpacesThreads = (threads: CopilotChatThread[]) => {
  return threads.filter(thread => {
    return thread.customCopilotID === undefined
  })
}
