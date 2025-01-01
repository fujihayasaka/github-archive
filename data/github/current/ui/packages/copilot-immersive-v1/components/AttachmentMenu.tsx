import {AgentsNotSupportedDialog, NoAgentsAvailableDialog} from '@github-ui/copilot-chat/components/AgentsDialogs'
import {KnowledgeSelectPanel} from '@github-ui/copilot-chat/components/KnowledgeSelectPanel'
import {ReferencesSelectPanel} from '@github-ui/copilot-chat/components/ReferencesSelectPanel'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useInsertAgent, type UseInsertAgentProps} from '@github-ui/copilot-chat/utils/agents-helpers'
import {isRepository} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {BookIcon, FileCodeIcon, PaperclipIcon, RepoIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useRefObjectAsForwardedRef} from '@primer/react'
import {forwardRef, useRef, useState} from 'react'

import {AgentMenu} from './AgentMenu'
import type {AttachmentMenuPanelType} from './AttachmentMenuPanelType'
import {RepoSelectPanel} from './RepoSelectPanel'

type AttachmentMenuProps = UseInsertAgentProps

export const AttachmentMenu = forwardRef<HTMLButtonElement, AttachmentMenuProps>(
  function AttachmentMenu(props, forwardedRef) {
    const {inputRef} = props
    const [panel, setPanel] = useState<AttachmentMenuPanelType | null>(null)

    const anchorRef = useRef<HTMLButtonElement>(null)
    useRefObjectAsForwardedRef(forwardedRef, anchorRef)

    const state = useChatState()

    const referencesEnabled = isRepository(state.currentTopic)
    const shouldShowKnowledge =
      state.renderKnowledgeBases && ((state.currentTopic && isRepository(state.currentTopic)) || !state.currentTopic)

    const insertAgent = useInsertAgent(props)

    return (
      <div>
        <ActionMenu
          anchorRef={anchorRef}
          onOpenChange={open => {
            if (open && panel) setPanel(null)
          }}
        >
          <ActionMenu.Anchor>
            <IconButton
              icon={PaperclipIcon}
              variant="invisible"
              aria-label="Add attachments"
              onClick={() => {
                sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU', mode: 'immersive'})
              }}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay width="small" side="outside-top" align="end">
            <ActionList>
              <ActionList.Item
                onSelect={() => {
                  sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_REFERENCES', mode: 'immersive'})
                  setPanel('references')
                }}
                inactiveText={referencesEnabled ? undefined : 'First attach a repository'}
              >
                <ActionList.LeadingVisual>
                  <FileCodeIcon />
                </ActionList.LeadingVisual>
                Files and symbols&hellip;
              </ActionList.Item>
              <ActionList.Item
                onSelect={() => {
                  sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_REPOSITORIES', mode: 'immersive'})
                  setPanel('repositories')
                }}
              >
                <ActionList.LeadingVisual>
                  <RepoIcon />
                </ActionList.LeadingVisual>
                Repository&hellip;
              </ActionList.Item>
              {shouldShowKnowledge && (
                <ActionList.Item
                  onSelect={() => {
                    sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_KNOWLEDGE_BASES', mode: 'immersive'})
                    setPanel('knowledge-bases')
                  }}
                >
                  <ActionList.LeadingVisual>
                    <BookIcon />
                  </ActionList.LeadingVisual>
                  Knowledge base&hellip;
                </ActionList.Item>
              )}
              <AgentMenu
                onSelectPanel={value => setPanel(value)}
                // setTimeout required to pull focus after ActionMenu tries to return to anchor
                onSelectAgent={agent => setTimeout(() => insertAgent(agent.slug))}
              />
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>

        <ReferencesSelectPanel
          open={panel === 'references'}
          onOpenChange={val => setPanel(val ? 'references' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />

        <RepoSelectPanel
          open={panel === 'repositories'}
          onOpenChange={isOpen => setPanel(isOpen ? 'repositories' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />

        <KnowledgeSelectPanel
          disabledForPreviewModelsProps={{anchorRef}}
          emptyKnowledgeBaseProps={{anchorRef}}
          open={panel === 'knowledge-bases'}
          onOpenChange={val => setPanel(val ? 'knowledge-bases' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />

        {panel === 'no-agents-available' && <NoAgentsAvailableDialog onClose={() => setPanel(null)} />}
        {panel === 'agents-not-supported' && <AgentsNotSupportedDialog onClose={() => setPanel(null)} />}
      </div>
    )
  },
)
