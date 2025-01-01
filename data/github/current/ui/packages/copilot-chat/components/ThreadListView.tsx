import {AlertIcon, CommentIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, Box, Button, Flash, IconButton, RelativeTime, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Dialog} from '@primer/react/experimental'
import {type Dispatch, type MutableRefObject, type SetStateAction, useMemo, useRef, useState} from 'react'

import {threadName} from '../utils/copilot-chat-helpers'
import type {CopilotChatManager} from '../utils/copilot-chat-manager'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {CopilotChatThread} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export function ThreadListView() {
  const state = useChatState()
  const manager = useChatManager()
  const threads = useMemo(() => manager.sortThreads(state.threads), [state.threads, manager])

  const [openDeleteConfirmationThreadId, setOpenDeleteConfirmationThreadId] = useState<string | null>(null)
  const returnFocusRef = useRef(null)

  if (state.threadsLoading.state === 'loading' && state.threads.size < 2) {
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
            {state.threads.size > 0 && (
              <ActionList sx={{overflowY: 'auto'}}>
                <ActionList.Group>
                  <ActionList.GroupHeading as="h3">Active conversations</ActionList.GroupHeading>
                  <ListView
                    threads={threads}
                    manager={manager}
                    openDeleteConfirmationThreadId={openDeleteConfirmationThreadId}
                    setOpenDeleteConfirmationThreadId={setOpenDeleteConfirmationThreadId}
                    returnFocusRef={returnFocusRef}
                  />
                </ActionList.Group>
              </ActionList>
            )}

            {state.threads.size === 0 && (
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

const ListView = ({
  threads,
  manager,
  openDeleteConfirmationThreadId,
  setOpenDeleteConfirmationThreadId,
  returnFocusRef,
}: {
  threads: CopilotChatThread[]
  manager: CopilotChatManager
  openDeleteConfirmationThreadId: string | null
  setOpenDeleteConfirmationThreadId: Dispatch<SetStateAction<string | null>>
  returnFocusRef: MutableRefObject<null>
}) => {
  return (
    <>
      {threads.map(thread => {
        return (
          <Box sx={{display: 'flex'}} key={thread.id}>
            <ActionList.Item key={thread.id} onSelect={() => manager.selectThread(thread)}>
              <ActionList.LeadingVisual>
                <CommentIcon />
              </ActionList.LeadingVisual>
              {threadName(thread)}
              <ActionList.TrailingVisual>
                <RelativeTime date={new Date(Date.parse(thread.updatedAt))} format="relative" />
              </ActionList.TrailingVisual>
            </ActionList.Item>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              unsafeDisableTooltip
              data-testid={`delete-thread-button-${thread.id}`}
              ref={returnFocusRef}
              onClick={() => setOpenDeleteConfirmationThreadId(thread.id)}
              sx={{p: 2, mr: 2}}
              variant="invisible"
              icon={TrashIcon}
              aria-label={`Delete conversation: "${threadName(thread)}"`}
              tooltipDirection="nw"
            />
            {openDeleteConfirmationThreadId === thread.id && (
              <div data-testid={`delete-thread-dialog-${thread.id}`}>
                <Dialog
                  title="Delete conversation"
                  width="small"
                  onClose={() => setOpenDeleteConfirmationThreadId(null)}
                  returnFocusRef={returnFocusRef}
                  footerButtons={[
                    {
                      buttonType: 'default',
                      content: 'Cancel',
                      onClick: () => setOpenDeleteConfirmationThreadId(null),
                    },
                    {
                      buttonType: 'danger',
                      content: 'Delete',
                      // eslint-disable-next-line @typescript-eslint/no-misused-promises
                      onClick: async () => {
                        await manager.deleteThreadKeepSelection(thread)
                        setOpenDeleteConfirmationThreadId(null)
                      },
                      autoFocus: true,
                    },
                  ]}
                >
                  Are you sure? This can’t be undone.
                </Dialog>
              </div>
            )}
          </Box>
        )
      })}
    </>
  )
}
