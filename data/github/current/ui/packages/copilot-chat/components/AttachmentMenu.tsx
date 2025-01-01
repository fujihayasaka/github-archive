import {sendEvent} from '@github-ui/hydro-analytics'
import {BookIcon, FileCodeIcon, ImageIcon, RepoIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {type RefObject, useEffect, useRef} from 'react'

import {useInsertAgent, type UseInsertAgentProps} from '../utils/agents-helpers'
import {isRepository} from '../utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {CopilotImageAttacher} from '../utils/copilot-image-attacher'
import {useChatAutocomplete} from '../utils/CopilotChatAutocompleteContext'
import {useChatState, useChatStateValues} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {AgentMenu} from './AgentMenu'
import {AgentsNotSupportedDialog, NoAgentsAvailableDialog} from './AgentsDialogs'
import type {AttachmentMenuPanelType} from './AttachmentMenuPanelType'
import {KnowledgeSelectPanel} from './KnowledgeSelectPanel'
import {COPILOT_CHAT_MENU_PORTAL_ROOT} from './PortalContainerUtils'
import {MultistepReferencesSelectPanel, TopicReferencesSelectPanel} from './ReferencesSelectPanel'
import {RepoReferencesSelectPanel, RepoTopicSelectPanel} from './RepoSelectPanel'

interface AttachmentMenuProps extends UseInsertAgentProps {
  panel: AttachmentMenuPanelType | null
  onPanelChange: React.Dispatch<React.SetStateAction<AttachmentMenuPanelType | null>>
  anchorRef: RefObject<HTMLButtonElement>
}

export function AttachmentMenu({panel, onPanelChange: setPanel, anchorRef, ...props}: AttachmentMenuProps) {
  const {inputRef} = props
  const manager = useChatManager()
  const state = useChatState()
  const autocomplete = useChatAutocomplete()

  const referencesEnabled = copilotFeatureFlags.topicsAsReferences ? true : isRepository(state.currentTopic)
  const shouldShowKnowledge =
    state.renderKnowledgeBases && ((state.currentTopic && isRepository(state.currentTopic)) || !state.currentTopic)

  // For now, we are focused on building out image support in immersive mode only, and only for supported models.
  const {model} = useChatStateValues('model')
  const shouldShowImages =
    (copilotFeatureFlags.attachImagesImmersive && state.mode === 'immersive' && !!model.capabilities.supports.vision) ||
    false

  const insertAgent = useInsertAgent(props)

  const imagesInputRef = useRef<HTMLInputElement>(null)

  const abortController = useRef<AbortController | null>(null)
  // If we unmount, abort any inflight uploads
  useEffect(
    () => () => {
      abortController.current?.abort()
    },
    [],
  )

  return (
    <div>
      {shouldShowImages && (
        <>
          <input
            id="image-uploader"
            hidden
            ref={imagesInputRef}
            type="file"
            accept={CopilotImageAttacher.getAllowedImageFileExtensions(model)}
            onChange={e => {
              if (!e.target.files) return
              const file = e.target.files[0]
              // We want to make sure this onChange handler is fired every time a selection is made, even if the
              // same file is selected twice in a row.
              e.currentTarget.value = ''
              if (!file) return
              const attacher = new CopilotImageAttacher(state, manager, autocomplete)
              const controller = (abortController.current ||= new AbortController())
              void attacher.addImageAttachment(file, controller.signal, 'menu')
            }}
          />
        </>
      )}
      <ActionMenu
        anchorRef={anchorRef}
        open={panel === 'attachment-types'}
        onOpenChange={newOpen =>
          setPanel(currentOpen => {
            // The menu should only be able to close the menu, not the other panel types. Otherwise it will autoclose
            // the dialogs as soon as they open as it tries to close itself.
            if (newOpen && currentOpen === null) return 'attachment-types'
            if (!newOpen && currentOpen === 'attachment-types') return null
            return currentOpen
          })
        }
      >
        <ActionMenu.Overlay
          width="small"
          side="outside-top"
          align="end"
          portalContainerName={state.mode === 'assistive' ? COPILOT_CHAT_MENU_PORTAL_ROOT : undefined}
        >
          <ActionList>
            <ActionList.Item
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_REFERENCES', mode: state.mode})
                setPanel('references')
              }}
              inactiveText={referencesEnabled ? undefined : 'First attach a repository'}
            >
              <ActionList.LeadingVisual>
                <FileCodeIcon />
              </ActionList.LeadingVisual>
              Files, folders, and symbols&hellip;
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_REPOSITORIES', mode: state.mode})
                setPanel('repositories')
              }}
            >
              <ActionList.LeadingVisual>
                <RepoIcon />
              </ActionList.LeadingVisual>
              {copilotFeatureFlags.topicsAsReferences ? 'Repositories' : 'Repository'}&hellip;
            </ActionList.Item>
            {shouldShowKnowledge && (
              <ActionList.Item
                onSelect={() => {
                  sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_KNOWLEDGE_BASES', mode: state.mode})
                  setPanel('knowledge-bases')
                }}
              >
                <ActionList.LeadingVisual>
                  <BookIcon />
                </ActionList.LeadingVisual>
                {copilotFeatureFlags.topicsAsReferences ? 'Knowledge bases' : 'Knowledge base'}&hellip;
              </ActionList.Item>
            )}
            {shouldShowImages && (
              <ActionList.Item
                onSelect={() => {
                  sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_IMAGES', mode: state.mode})
                  // ensure panel is closed before file input is open
                  setPanel(null)
                  imagesInputRef.current?.click()
                }}
              >
                <ActionList.LeadingVisual>
                  <ImageIcon />
                </ActionList.LeadingVisual>
                Image&hellip;
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

      {copilotFeatureFlags.topicsAsReferences ? (
        <MultistepReferencesSelectPanel
          open={panel === 'references'}
          onOpenChange={val => setPanel(val ? 'references' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />
      ) : (
        <TopicReferencesSelectPanel
          open={panel === 'references'}
          onOpenChange={val => setPanel(val ? 'references' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />
      )}

      {copilotFeatureFlags.topicsAsReferences ? (
        <RepoReferencesSelectPanel
          open={panel === 'repositories'}
          onOpenChange={val => setPanel(val ? 'repositories' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />
      ) : (
        <RepoTopicSelectPanel
          open={panel === 'repositories'}
          onOpenChange={val => setPanel(val ? 'repositories' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
        />
      )}

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
}
