import {KebabHorizontalIcon, LinkIcon, PaperclipIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Truncate} from '@primer/react'
import type React from 'react'
import {useCallback, useMemo, useRef, useState} from 'react'

import {isDocset, referenceID, referenceName, referenceURL, validReferenceURL} from '../utils/copilot-chat-helpers'
import type {CopilotChatReference} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {ActionMenuOverlay, COPILOT_CHAT_MESSAGES_MENU_PORTAL_ROOT} from './PortalContainerUtils'
import {iconForReference} from './ReferenceToken'

export interface ChatReferenceProps {
  reference: CopilotChatReference
}

export function OutputReference({reference}: ChatReferenceProps) {
  const state = useChatState() as ReturnType<typeof useChatState> | undefined // if we're run in tests without context, this will be undefined
  const manager = useChatManager()
  const actionButtonRef = useRef<HTMLButtonElement | null>(null)
  const [moreMenuOpen, setMoreMenuOpen] = useState(false)

  const mode = state?.mode ?? 'assistive'

  const {currentReferences} = state ?? {currentReferences: []}
  const selectedRefIDs = useMemo(() => currentReferences.map(r => referenceID(r)), [currentReferences])
  const thisRefID = useMemo(() => referenceID(reference), [reference])
  const isRepoInstructions = useMemo(() => reference.type === 'repo-instructions', [reference])
  const isOrgInstructions = useMemo(() => reference.type === 'org-instructions', [reference])

  const showTrailingVisual = !isRepoInstructions && !isOrgInstructions && reference.type !== 'web-search-result'
  const isInCurrentReferences = useMemo(
    () => isRepoInstructions || isOrgInstructions || selectedRefIDs.includes(thisRefID),
    [isRepoInstructions, isOrgInstructions, selectedRefIDs, thisRefID],
  )
  const handleAddReference = useCallback(
    (e: React.SyntheticEvent) => {
      e.stopPropagation()
      if (isInCurrentReferences) return
      manager.addReference(reference, 'refMenu')
    },
    [manager, reference, isInCurrentReferences],
  )

  const refURL = referenceURL(reference)
  const validURL = validReferenceURL(refURL)
  const Icon = iconForReference(reference, isDocset(state?.currentTopic))

  let filePath
  if (copilotFeatureFlags.newImmersiveReferencesUI) {
    switch (reference.type) {
      case 'file':
      case 'snippet': {
        filePath = `${reference.repoName}`

        const index = reference.path.lastIndexOf('/')
        if (index !== -1) {
          filePath = `${filePath}/${reference.path.substring(0, index)}`
        }
        break
      }
      case 'web-search-result':
        filePath = new URL(reference.url, window.location.origin).hostname.replace(/^www\./, '')
        break
    }
  }

  const referenceTitle = referenceName(reference)

  return (
    <ActionList.LinkItem
      href={refURL}
      rel="noopener"
      sx={{wordBreak: 'break-word', width: '100%'}}
      className="reference-action"
      target={mode === 'immersive' || reference.type === 'third-party' ? '_blank' : undefined}
    >
      {Icon && (
        <ActionList.LeadingVisual>
          <Icon />
        </ActionList.LeadingVisual>
      )}

      <Truncate
        title={referenceTitle}
        maxWidth="100%"
        className={copilotFeatureFlags.newImmersiveReferencesUI ? 'text-semibold' : undefined}
      >
        {referenceTitle}
        {filePath && <span className="color-fg-muted ml-2">{filePath}</span>}
      </Truncate>

      {showTrailingVisual && (
        <ActionList.TrailingAction
          onClick={() => setMoreMenuOpen(true)}
          icon={KebabHorizontalIcon}
          label="More reference options"
          ref={actionButtonRef}
        />
      )}
      {showTrailingVisual && (
        <ActionMenu anchorRef={actionButtonRef} open={moreMenuOpen} onOpenChange={setMoreMenuOpen}>
          <ActionMenuOverlay portalContainerName={COPILOT_CHAT_MESSAGES_MENU_PORTAL_ROOT}>
            <ActionList>
              {validURL &&
                (mode === 'immersive' || ['third-party', 'folder', 'repository', 'docset'].includes(reference.type) ? (
                  <ActionList.LinkItem href={refURL} rel="noopener" target="_blank">
                    <ActionList.LeadingVisual>
                      <LinkIcon />
                    </ActionList.LeadingVisual>
                    Open
                  </ActionList.LinkItem>
                ) : (
                  <ActionList.Item
                    onSelect={() => {
                      manager.selectReference(reference)
                    }}
                  >
                    <ActionList.LeadingVisual>
                      <LinkIcon />
                    </ActionList.LeadingVisual>
                    Preview
                  </ActionList.Item>
                ))}
              <ActionList.Item onSelect={handleAddReference} disabled={isInCurrentReferences}>
                <ActionList.LeadingVisual>
                  <PaperclipIcon />
                </ActionList.LeadingVisual>
                Attach to chat
              </ActionList.Item>
            </ActionList>
          </ActionMenuOverlay>
        </ActionMenu>
      )}
    </ActionList.LinkItem>
  )
}
