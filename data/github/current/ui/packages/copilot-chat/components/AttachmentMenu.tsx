import {sendEvent} from '@github-ui/hydro-analytics'
import {testIdProps} from '@github-ui/test-id-props'
import {BookIcon, FileCodeIcon, ImageIcon, RepoIcon, UploadIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {memo, type RefObject, useRef} from 'react'

import {useSelectedCustomCopilotId} from '../hooks/use-selected-custom-copilot-id'
import {useSupportedAttachmentTypes} from '../hooks/use-supported-attachment-types'
import {useInsertAgent, type UseInsertAgentProps} from '../utils/agents-helpers'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {CopilotImageAttacher} from '../utils/copilot-image-attacher'
import {CopilotTextAttacher} from '../utils/copilot-text-attacher'
import {useChatState, useChatStateValues} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {isCopilotSpacePath} from '../utils/custom-copilots-helpers'
import {AgentMenu} from './AgentMenu'
import {AgentsNotSupportedDialog, NoAgentsAvailableDialog} from './AgentsDialogs'
import type {AttachmentMenuPanelType} from './AttachmentMenuPanelType'
import {KnowledgeSelectPanel} from './KnowledgeSelectPanel'
import {COPILOT_CHAT_MENU_PORTAL_ROOT} from './PortalContainerUtils'
import {getLabelText, MultistepReferencesSelectPanel, TopicReferencesSelectPanel} from './ReferencesSelectPanel'
import {RepoReferencesSelectPanel, RepoTopicSelectPanel} from './RepoSelectPanel'

export interface AttachmentMenuProps extends UseInsertAgentProps {
  panel: AttachmentMenuPanelType | null
  onPanelChange: React.Dispatch<React.SetStateAction<AttachmentMenuPanelType | null>>
  anchorRef: RefObject<HTMLButtonElement>
}

export const AttachmentMenu = memo(({panel, onPanelChange: setPanel, anchorRef, ...props}: AttachmentMenuProps) => {
  const {inputRef} = props
  const manager = useChatManager()
  const state = useChatState()
  const {supportedAttachmentTypes, supportedReferenceTypes} = useSupportedAttachmentTypes()

  // For now, we are focused on building out image support in immersive mode only, and only for supported models.
  const {model} = useChatStateValues('model')
  const imageUploadsEnabled =
    (copilotFeatureFlags.attachImagesImmersive && state.mode === 'immersive' && !!model.capabilities.supports.vision) ||
    false
  const multipleImageUploadsEnabled = copilotFeatureFlags.attachMultipleImages
  const textUploadsEnabled = copilotFeatureFlags.pasteTextFiles

  const insertAgent = useInsertAgent(props)

  const fileInputRef = useRef<HTMLInputElement>(null)

  const customCopilotId = useSelectedCustomCopilotId()
  // Prevent thread selection when we attach images if we're in the space's page
  const preventThreadSelectionOnCreation = Boolean(customCopilotId && isCopilotSpacePath())

  return (
    <div>
      {supportedAttachmentTypes.includes('upload') && (
        <input
          id="image-uploader"
          {...testIdProps('image-uploader')}
          hidden
          ref={fileInputRef}
          type="file"
          accept={[
            imageUploadsEnabled ? CopilotImageAttacher.getAllowedImageFileExtensions(model) : '',
            textUploadsEnabled ? CopilotTextAttacher.getTextFileExtensions() : '',
          ].join(',')}
          multiple={textUploadsEnabled || multipleImageUploadsEnabled}
          onChange={e => {
            if (!e.target.files) return

            // Split the image files out of the other files so we can handle them separately.
            const [imageFiles, otherFiles] = CopilotImageAttacher.getAllowedFiles([...e.target.files], model)

            // Files that we do not support uploading. We will log each of these later.
            const unsupportedFiles = []

            if (imageUploadsEnabled) {
              const attacher = new CopilotImageAttacher(state, manager)
              void attacher.addImageAttachments(imageFiles, 'menu', customCopilotId, preventThreadSelectionOnCreation)
            } else {
              unsupportedFiles.push(...imageFiles)
            }

            if (textUploadsEnabled) {
              for (const file of otherFiles) {
                const attacher = new CopilotTextAttacher(manager)
                void attacher.addAttachment(file)
              }
            } else {
              unsupportedFiles.push(...otherFiles)
            }

            for (const file of unsupportedFiles) {
              sendEvent('dotcom_chat.upload_unsupported_file', {name: file.name, type: file.type, size: file.size})
            }

            // We want to make sure this onChange handler is fired every time a selection is made, even if the
            // same file is selected twice in a row.
            e.currentTarget.value = ''
          }}
        />
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
          align={'start'}
          portalContainerName={state.mode === 'assistive' ? COPILOT_CHAT_MENU_PORTAL_ROOT : undefined}
        >
          <ActionList>
            {supportedAttachmentTypes.includes('repositories') && (
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
            )}
            <ActionList.Item
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_REFERENCES', mode: state.mode})
                setPanel('references')
              }}
              inactiveText={supportedAttachmentTypes.includes('references') ? undefined : 'First attach a repository'}
            >
              <ActionList.LeadingVisual>
                <FileCodeIcon />
              </ActionList.LeadingVisual>
              {getLabelText(supportedReferenceTypes)}&hellip;
            </ActionList.Item>
            {supportedAttachmentTypes.includes('knowledge-bases') && (
              <ActionList.Item
                onSelect={() => {
                  sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_KNOWLEDGE_BASES', mode: state.mode})
                  setPanel('knowledge-bases')
                }}
              >
                <ActionList.LeadingVisual>
                  <BookIcon />
                </ActionList.LeadingVisual>
                <span {...testIdProps('knowledge-bases-action-list-item')}>
                  {copilotFeatureFlags.topicsAsReferences ? 'Knowledge bases' : 'Knowledge base'}&hellip;
                </span>
              </ActionList.Item>
            )}
            {supportedAttachmentTypes.includes('upload') && (
              <>
                <ActionList.Divider />
                <ActionList.Item
                  onSelect={() => {
                    sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_IMAGES', mode: state.mode})
                    // ensure panel is closed before file input is open
                    setPanel(null)
                    fileInputRef.current?.click()
                  }}
                >
                  <ActionList.LeadingVisual>
                    {textUploadsEnabled ? <UploadIcon /> : <ImageIcon />}
                  </ActionList.LeadingVisual>
                  {textUploadsEnabled ? 'Upload from computer' : 'Image…'}
                </ActionList.Item>
              </>
            )}
            {supportedAttachmentTypes.includes('agents') && (
              <>
                <ActionList.Divider />
                <AgentMenu
                  onSelectPanel={value => setPanel(value)}
                  // setTimeout required to pull focus after ActionMenu tries to return to anchor
                  onSelectAgent={agent => setTimeout(() => insertAgent(agent.slug))}
                />
              </>
            )}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      {copilotFeatureFlags.topicsAsReferences ? (
        <MultistepReferencesSelectPanel
          open={panel === 'references'}
          onOpenChange={val => setPanel(val ? 'references' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
          supportedReferenceTypes={supportedReferenceTypes}
        />
      ) : (
        <TopicReferencesSelectPanel
          open={panel === 'references'}
          onOpenChange={val => setPanel(val ? 'references' : null)}
          submitReturnFocusRef={inputRef}
          cancelReturnFocusRef={anchorRef}
          supportedReferenceTypes={supportedReferenceTypes}
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

      {supportedAttachmentTypes.includes('knowledge-bases') && (
        <KnowledgeSelectPanel
          disabledForPreviewModelsProps={{anchorRef}}
          emptyKnowledgeBaseProps={{anchorRef}}
          open={panel === 'knowledge-bases'}
          onOpenChange={val => setPanel(val ? 'knowledge-bases' : null)}
          anchorRef={anchorRef}
        />
      )}

      {panel === 'no-agents-available' && <NoAgentsAvailableDialog onClose={() => setPanel(null)} />}
      {panel === 'agents-not-supported' && <AgentsNotSupportedDialog onClose={() => setPanel(null)} />}
    </div>
  )
})

AttachmentMenu.displayName = 'AttachmentMenu'
