import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {KebabHorizontalIcon, LinkIcon, PaperclipIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import type React from 'react'
import {useCallback, useMemo, useRef} from 'react'

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

  const mode = state?.mode ?? 'assistive'
  const clickHandler = useCallback((e: React.SyntheticEvent) => {
    // If the user is clicking on the action menu, don't let the event bubble up and select the reference.
    if (e.target instanceof Node && actionButtonRef.current?.contains(e.target)) {
      e.stopPropagation()
      e.preventDefault()
    }
  }, [])

  const {currentReferences} = state ?? {currentReferences: []}
  const selectedRefIDs = useMemo(() => currentReferences.map(r => referenceID(r)), [currentReferences])
  const thisRefID = useMemo(() => referenceID(reference), [reference])
  const isRepoInstructions = useMemo(() => reference.type === 'repo-instructions', [reference])
  const isInCurrentReferences = useMemo(
    () => isRepoInstructions || selectedRefIDs.includes(thisRefID),
    [isRepoInstructions, selectedRefIDs, thisRefID],
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
  if (copilotFeatureFlags.newImmersiveReferencesUI && (reference.type === 'file' || reference.type === 'snippet')) {
    filePath = `${reference.repoName}`

    const index = reference.path.lastIndexOf('/')
    if (index !== -1) {
      filePath = `${filePath}/${reference.path.substring(0, index)}`
    }
  }
  return (
    <ActionList.LinkItem
      onClick={clickHandler}
      href={refURL}
      rel="noopener"
      sx={{wordBreak: 'break-word'}}
      className="reference-action"
      target={mode === 'immersive' || reference.type === 'third-party' ? '_blank' : undefined}
    >
      {Icon && (
        <ActionList.LeadingVisual>
          <Icon />
        </ActionList.LeadingVisual>
      )}

      <span className={copilotFeatureFlags.newImmersiveReferencesUI ? 'text-semibold' : undefined}>
        {referenceName(reference)}
      </span>

      {filePath && <span className="color-fg-muted ml-2">{filePath}</span>}

      {!isRepoInstructions && (
        <ActionList.TrailingVisual>
          <ActionMenu anchorRef={actionButtonRef}>
            <ActionMenu.Anchor>
              <IconButtonWithTooltip
                icon={KebabHorizontalIcon}
                sx={{height: 20}}
                variant="invisible"
                size="small"
                aria-label="More reference options"
                label="More reference options"
                tooltipDirection="nw"
                className="reference-action"
              />
            </ActionMenu.Anchor>

            <ActionMenuOverlay portalContainerName={COPILOT_CHAT_MESSAGES_MENU_PORTAL_ROOT}>
              <ActionList>
                {validURL &&
                  (mode === 'immersive' ||
                  ['third-party', 'folder', 'repository', 'docset'].includes(reference.type) ? (
                    <ActionList.LinkItem
                      href={refURL}
                      onClick={e => {
                        // `clickHandler` will try to open this link in a dialog if the event gets to it
                        e.stopPropagation()
                      }}
                      rel="noopener"
                      target="_blank"
                    >
                      <ActionList.LeadingVisual>
                        <LinkIcon />
                      </ActionList.LeadingVisual>
                      Open
                    </ActionList.LinkItem>
                  ) : (
                    <ActionList.Item
                      onSelect={e => {
                        // `clickHandler` will try to open this link in a dialog if the event gets to it
                        e.stopPropagation()
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
        </ActionList.TrailingVisual>
      )}
    </ActionList.LinkItem>
  )
}
