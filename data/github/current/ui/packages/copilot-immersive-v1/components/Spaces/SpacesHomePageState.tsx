import {ChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH, threadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {useNavigate} from '@github-ui/use-navigate'
import {CommentIcon, PlusIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import {useEffect, useMemo, useState} from 'react'

import {clearThreadTimePatch, getThreadTimePatch} from '../../utils/local-storage'
import {ConversationLoader} from '../ConversationLoader'
import {AddReferenceMenu} from './AddReferenceMenu'
import {EditInstructionsDialog} from './EditInstructionsDialog'
import {ReferencesTable} from './ReferencesTable'
import classes from './SpacesHomePageState.module.css'

interface SpacesHomePageStateProps {
  selectedThreadID: string | null
  textAreaRef: React.RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
}

export const SpacesHomePageState = (props: SpacesHomePageStateProps) => {
  const {selectedThreadID, textAreaRef, onSubmit} = props

  const navigate = useNavigate()
  const manager = useChatManager()
  const state = useChatState()
  const {customCopilotId, threads, findFileWorkerPath} = state

  const [loading, setLoading] = useState(true)
  const currentSpace = loading ? null : state.customCopilots?.find(space => space.id === customCopilotId)

  const {protectedOrganizations} = currentSpace || {}

  const [showEditInstructionsDialog, setShowEditInstructionsDialog] = useState(false)

  useEffect(() => {
    async function fetchData() {
      if (typeof customCopilotId === 'number') {
        // we are fetching it here, because the initial list call doesn't include references list
        const customCopilot = await manager.fetchCustomCopilot(customCopilotId)
        manager.dispatch({
          type: 'SET_CUSTOM_COPILOT',
          customCopilot,
        })
        setLoading(false)
      }
    }
    void fetchData()
  }, [customCopilotId, manager])

  const items = useMemo(() => {
    patchThreadTime(threads)
    const filteredThreads = new Map(
      Array.from(threads.entries()).filter(k => {
        return k[1].customCopilotID === customCopilotId
      }),
    )
    return manager.sortThreads(filteredThreads).map(thread => ({
      id: thread.id,
      text: threadName(thread),
      href: `${COPILOT_PATH}/c/${thread.id}`,
      date: new Date(thread.updatedAt),
    }))
  }, [threads, customCopilotId, manager])

  if (!currentSpace) {
    return <ConversationLoader />
  }

  return (
    <>
      <div className={classes.container}>
        <div className={classes.banner}>
          {protectedOrganizations && (
            <SingleSignOnBanner
              protectedOrgs={protectedOrganizations}
              redirectURI={() => `/search/refresh_blackbird_caches?return_to=${encodeURIComponent(location.href)}`}
            />
          )}
        </div>

        <h2>{currentSpace.name}</h2>
        {currentSpace.description && <p className={classes.description}>{currentSpace.description}</p>}
        <div className="width-full">
          <ChatInput
            key={selectedThreadID}
            textAreaRef={textAreaRef}
            onSubmit={onSubmit}
            isStreaming={!!state.streamingMessage}
            size="small"
          />
        </div>
        <div className={classes.details}>
          <div className={classes.left}>
            <div className={classes.instructions}>
              <p className={classes.instructionsTitle}>
                Instructions
                <Button size={'small'} onClick={() => setShowEditInstructionsDialog(true)}>
                  Edit
                </Button>
              </p>
              {currentSpace.generalInstructions ? (
                <p className={classes.instructionsText}>{currentSpace.generalInstructions}</p>
              ) : (
                <p className={classes.emptyText}>No instructions added</p>
              )}
            </div>
            <div className={classes.references}>
              <p className={classes.referencesTitle} id="references-title">
                References
                <AddReferenceMenu copilotSpace={currentSpace} findFileWorkerPath={findFileWorkerPath}>
                  <Button leadingVisual={PlusIcon} size={'small'}>
                    Add
                  </Button>
                </AddReferenceMenu>
              </p>
              {currentSpace.resources.length > 0 ? (
                <ReferencesTable copilotSpace={currentSpace} />
              ) : (
                <p className={classes.referencesText}>No references added</p>
              )}
            </div>
          </div>
          <div className={classes.right}>
            <div className={classes.conversations}>
              <p className={classes.conversationsTitle}>Conversations</p>
              {items.length > 0 ? (
                <ActionList variant="full">
                  {items.map(item => (
                    <ActionList.LinkItem
                      key={item.id}
                      href={item.href}
                      onClick={event => {
                        event.preventDefault()
                        navigate(item.href)
                      }}
                    >
                      <ActionList.LeadingVisual>
                        <CommentIcon />
                      </ActionList.LeadingVisual>
                      {item.text}
                    </ActionList.LinkItem>
                  ))}
                </ActionList>
              ) : (
                <p className={classes.conversationsText}>No conversations yet</p>
              )}
            </div>
          </div>
        </div>
      </div>
      {showEditInstructionsDialog && (
        <EditInstructionsDialog copilotSpace={currentSpace} onClose={() => setShowEditInstructionsDialog(false)} />
      )}
    </>
  )
}

/**
 * When we create a new thread, we might reuse an older, empty thread. In that case, we need to update the thread's
 * updatedAt time to the current time so that it appears at the top of the thread list. We store this hack in local
 * storage so that it persists across page navigations.
 */
function patchThreadTime(threads: Map<string, CopilotChatThread>) {
  const patch = getThreadTimePatch()
  if (patch) {
    const thread = threads.get(patch.threadID)
    if (thread) {
      if (Date.parse(thread.updatedAt) <= patch.updatedAt) {
        thread.updatedAt = new Date(patch.updatedAt).toJSON()
      } else {
        clearThreadTimePatch()
      }
    }
  }
}
