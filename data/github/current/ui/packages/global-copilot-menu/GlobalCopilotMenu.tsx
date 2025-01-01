import {sendEvent} from '@github-ui/hydro-analytics'
import {ActionMenu, ActionList, Label} from '@primer/react'
import {ScreenFullIcon, CopilotIcon, GearIcon, TerminalIcon, CommandPaletteIcon} from '@primer/octicons-react'

import {
  useExternalAnchor,
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
} from '@github-ui/react-core/react-partial-anchor'
import {useState} from 'react'
import {EditorMenuItems} from './EditorMenuItems'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'

export interface GlobalCopilotMenuProps extends ReactPartialAnchorProps {
  chatVisibleSettingPath?: string
}

function ExternallyAnchoredGlobalCopilotMenu(props: PropsWithPartialAnchor<{}>) {
  const {ref: anchorRef, open, setOpen} = useExternalAnchor(props.reactPartialAnchor)

  return (
    <ActionMenu anchorRef={anchorRef} open={open} onOpenChange={setOpen}>
      <GlobalCopilotMenuOverlay />
    </ActionMenu>
  )
}

function GlobalCopilotMenuWithAnchor() {
  const [isOpen, setIsOpen] = useState(false)

  return (
    <ActionMenu open={isOpen} onOpenChange={setIsOpen}>
      <ActionMenu.Button leadingVisual={CopilotIcon} aria-label="Open Copilot…">
        {''}
      </ActionMenu.Button>
      <GlobalCopilotMenuOverlay />
    </ActionMenu>
  )
}

export function GlobalCopilotMenu(props: GlobalCopilotMenuProps) {
  if (props.reactPartialAnchor) {
    return <ExternallyAnchoredGlobalCopilotMenu {...props} reactPartialAnchor={props.reactPartialAnchor} />
  }

  return <GlobalCopilotMenuWithAnchor />
}

export function GlobalCopilotMenuOverlay() {
  const handleClick = (eventName: string) => {
    sendEvent('dotcom_chat.activate', {
      target: `GLOBAL_COPILOT_MENU_${eventName.toUpperCase()}`,
      mode: 'global_nav',
    })
  }

  return (
    <ActionMenu.Overlay align="end">
      <ActionList>
        <ActionList.Group>
          <ActionList.GroupHeading>New conversation</ActionList.GroupHeading>
          {/*<ActionList.LinkItem href="/copilot" onClick={() => handleClick('ASSISTIVE')}>
            <ActionList.LeadingVisual>
              <CommentIcon />
            </ActionList.LeadingVisual>
            Assistive
          </ActionList.LinkItem>*/}
          <ActionList.LinkItem href="/copilot" onClick={() => handleClick('FULLSCREEN')}>
            <ActionList.LeadingVisual>
              <ScreenFullIcon />
            </ActionList.LeadingVisual>
            Immersive
          </ActionList.LinkItem>
          {copilotFeatureFlags.taskOrientedAssistive && (
            <ActionList.Item
              onSelect={() => {
                handleClick('TASK_ORIENTED_ASSISTIVE')
                publishOpenCopilotChat({
                  id: 'copilot-task-oriented-assistive',
                  intent: CopilotChatIntents.conversation,
                  newThread: true,
                  references: [],
                })
              }}
            >
              <ActionList.LeadingVisual>
                <CommandPaletteIcon />
              </ActionList.LeadingVisual>
              Task
              <ActionList.TrailingVisual>
                <Label variant="accent">Staff</Label>
              </ActionList.TrailingVisual>
            </ActionList.Item>
          )}
        </ActionList.Group>

        <ActionList.Divider />

        <ActionMenu>
          <ActionMenu.Anchor>
            <ActionList.Item onSelect={() => handleClick('OPEN_WITH')}>
              <ActionList.LeadingVisual>
                <CopilotIcon />
              </ActionList.LeadingVisual>
              Open with
            </ActionList.Item>
          </ActionMenu.Anchor>
          <ActionMenu.Overlay>
            <ActionList>
              <EditorMenuItems onClick={id => handleClick(id)} />
              <ActionList.Divider />
              <ActionList.LinkItem
                href="https://docs.github.com/en/copilot/managing-copilot/configure-personal-settings/installing-github-copilot-in-the-cli"
                onClick={() => handleClick('CLI')}
              >
                CLI
                <ActionList.LeadingVisual>
                  <TerminalIcon />
                </ActionList.LeadingVisual>
              </ActionList.LinkItem>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>

        <ActionList.LinkItem href="/settings/copilot" onClick={() => handleClick('SETTINGS')}>
          Settings
          <ActionList.LeadingVisual>
            <GearIcon />
          </ActionList.LeadingVisual>
        </ActionList.LinkItem>
      </ActionList>
    </ActionMenu.Overlay>
  )
}
