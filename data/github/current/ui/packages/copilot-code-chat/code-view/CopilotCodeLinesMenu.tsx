import {isFeatureEnabled} from '@github-ui/feature-flags'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ButtonGroup} from '@primer/react'
import {useCallback, useState} from 'react'

import {publishAddCopilotChatReference, publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {
  CopilotChatIntents,
  type CopilotChatReference,
  type CopilotChatEventPayload,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {AskCopilotButton} from '../AskCopilotButton'
import styles from './CopilotCodeLinesMenu.module.css'

const DROPDOWN_BUTTON_ID = 'code-line-dropdown-copilot-button'

export default function CopilotCodeLinesMenu({
  copilotAccessAllowed,
  messageReference,
  hideDropdown,
  id,
}: {
  copilotAccessAllowed: boolean
  messageReference: CopilotChatReference
  hideDropdown?: boolean
  id?: string
}) {
  const [open, setOpen] = useState(false)
  const openingThreadSwitchEnable = isFeatureEnabled('copilot_chat_opening_thread_switch')

  const handleExplain = () => {
    publishOpenCopilotChat({
      content: 'Explain',
      intent: CopilotChatIntents.explain,
      references: [messageReference],
      id: DROPDOWN_BUTTON_ID,
    })
    setOpen(false)
  }

  const handleSuggest = () => {
    publishOpenCopilotChat({
      content: 'Suggest improvements to this code.',
      intent: CopilotChatIntents.suggest,
      references: [messageReference],
      id: DROPDOWN_BUTTON_ID,
    })
    setOpen(false)
  }

  const handleAskAbout = useCallback(() => {
    const payload: CopilotChatEventPayload = {
      intent: CopilotChatIntents.conversation,
      references: [messageReference],
      id,
    }

    publishOpenCopilotChat(payload)
    setOpen(false)
  }, [id, messageReference])

  const handleAddReferenceCallback = () => {
    if (openingThreadSwitchEnable) {
      handleAttachReference(messageReference, DROPDOWN_BUTTON_ID)
    } else {
      handleAddReference(messageReference, true, DROPDOWN_BUTTON_ID)
    }
    setOpen(false)
  }

  return copilotAccessAllowed ? (
    <ButtonGroup className={hideDropdown ? 'pr-0' : ''}>
      <AskCopilotButton
        referenceType={messageReference.type}
        onClick={hideDropdown ? () => handleAddReference(messageReference, true, id) : handleAskAbout}
        id={id}
      />
      {hideDropdown ? undefined : (
        <ActionMenu open={open} onOpenChange={setOpen}>
          <ActionMenu.Button
            // This is all hacky and I wish we could use ActionMenu.Anchor
            // But ActionMenu.Anchor doesn't accept an ID parameter
            // TODO: revert back to how this was before once https://github.com/primer/react/issues/4299 is fixed
            // the empty child fragment is load bearing for button group styles and `ActionMenu.Button` requires a child element
            id={DROPDOWN_BUTTON_ID}
            trailingAction={TriangleDownIcon}
            size="small"
            aria-label="Copilot menu"
            className={styles['menu-button']}
          >
            <></>
          </ActionMenu.Button>
          <ActionMenu.Overlay
            align="end"
            onKeyDown={e => {
              // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
              if (e.key === 'Escape') {
                e?.stopPropagation()
                setOpen(false)
              }
            }}
          >
            <ActionList>
              <ActionList.Item onSelect={handleExplain}>Explain</ActionList.Item>
              <ActionList.Item onSelect={handleSuggest}>Suggest improvements</ActionList.Item>
              <ActionList.Divider />
              <ActionList.Item onSelect={handleAddReferenceCallback}>Attach to current thread</ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      )}
    </ButtonGroup>
  ) : null
}

export const handleAttachReference = (messageReference: CopilotChatReference, id?: string) => {
  publishAddCopilotChatReference(messageReference, false, id)
  publishOpenCopilotChat({intent: CopilotChatIntents.conversation, id, attachThread: true})
}

export const handleAddReference = (messageReference: CopilotChatReference, shouldAppend?: boolean, id?: string) => {
  if (shouldAppend) {
    publishAddCopilotChatReference(messageReference, true, id)
    publishOpenCopilotChat({intent: CopilotChatIntents.conversation, id})
  } else {
    publishOpenCopilotChat({intent: CopilotChatIntents.conversation, references: [messageReference], id})
  }
}
