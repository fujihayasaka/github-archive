import {sendEvent} from '@github-ui/hydro-analytics'
import {ActionMenu, ActionList, Label} from '@primer/react'
import {
  ScreenFullIcon,
  CopilotIcon,
  GearIcon,
  TerminalIcon,
  CommandPaletteIcon,
  CommentIcon,
  DownloadIcon,
} from '@primer/octicons-react'
import {EditorMenuItems, recordMenuClick} from './EditorMenuItems'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {usePlan} from './use-plan'
import {COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'

import {CommandActionListItem, GlobalCommands} from '@github-ui/ui-commands'
import {
  useExternalAnchor,
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
} from '@github-ui/react-core/react-partial-anchor'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import styles from './GlobalCopilotMenu.module.css'
import {SpacesIcon} from '@github-ui/pacer/CustomIcon'

const analyticsMenuLocation = 'global_copilot_menu'
const mode = 'global_nav'

const recordClick = (id: string) => {
  if (copilotFeatureFlags.freeToPaidTelemetry) {
    recordMenuClick({eventName: id, menuLocation: analyticsMenuLocation, mode})
  } else {
    sendEvent('dotcom_chat.activate', {
      target: `GLOBAL_COPILOT_MENU_${id}`,
      mode: 'global_nav',
    })
  }
}

const openAssistive = () => {
  publishOpenCopilotChat({
    id: 'copilot-assistive',
    intent: CopilotChatIntents.conversation,
    newThread: true,
  })
  recordClick('ASSISTIVE')
}

const openImmersive = () => {
  window.location.href = '/copilot'
  sendEvent('dotcom_chat.activate', {
    target: `GLOBAL_COPILOT_MENU_FULLSCREEN`,
    mode: 'global_nav',
  })
  recordClick('IMMERSIVE')
}

function ExternallyAnchoredGlobalCopilotMenu(props: PropsWithPartialAnchor<{}>) {
  const {ref: anchorRef, open, setOpen} = useExternalAnchor(props.reactPartialAnchor)

  return (
    <ActionMenu anchorRef={anchorRef} open={open} onOpenChange={setOpen}>
      <GlobalCopilotMenuOverlay />
    </ActionMenu>
  )
}

export function GlobalCopilotMenuWithAnchor() {
  return (
    <ActionMenu>
      <ActionMenu.Button leadingVisual={CopilotIcon} aria-label="Open Copilot…">
        {''}
      </ActionMenu.Button>
      <GlobalCopilotMenuOverlay />
    </ActionMenu>
  )
}

export function GlobalCopilotMenu({reactPartialAnchor}: ReactPartialAnchorProps) {
  return (
    <ErrorBoundary fallback={null}>
      <GlobalCommands
        commands={{
          'copilot-chat:open-assistive': openAssistive,
          'copilot-chat:open-immersive': openImmersive,
        }}
      />
      {reactPartialAnchor ? (
        <ExternallyAnchoredGlobalCopilotMenu reactPartialAnchor={reactPartialAnchor} />
      ) : (
        <GlobalCopilotMenuWithAnchor />
      )}
    </ErrorBoundary>
  )
}

function renderPlanType(plan: CopilotPlan | undefined) {
  switch (plan) {
    case CopilotPlan.IndividualProPlus:
      return <Label className={styles.proLabel}>Pro+</Label>
    case CopilotPlan.IndividualPro:
      return <Label className={styles.proLabel}>Pro</Label>
    case CopilotPlan.IndividualFree:
      return <Label>Free</Label>
    default:
      return null
  }
}

export function YourCopilotButton() {
  const plan = usePlan()

  return (
    <ActionList.LinkItem href="/settings/copilot" onClick={() => recordClick('SETTINGS')}>
      Your Copilot
      <ActionList.LeadingVisual>
        <CopilotIcon />
      </ActionList.LeadingVisual>
      {plan && <ActionList.TrailingVisual>{renderPlanType(plan)}</ActionList.TrailingVisual>}
    </ActionList.LinkItem>
  )
}

function GlobalCopilotMenuOverlay() {
  return (
    <ActionMenu.Overlay align="end">
      <ActionList style={{width: '15rem'}}>
        <ActionList.Group>
          <ActionList.GroupHeading>New conversation in</ActionList.GroupHeading>
          <CommandActionListItem commandId="copilot-chat:open-assistive" leadingVisual={<CommentIcon />}>
            Assistive
          </CommandActionListItem>

          {!copilotFeatureFlags.headerButtonToImmersive && (
            <ActionList.LinkItem href="/copilot" onClick={() => recordClick('FULLSCREEN')}>
              <ActionList.LeadingVisual>
                <ScreenFullIcon />
              </ActionList.LeadingVisual>
              Immersive
            </ActionList.LinkItem>
          )}

          <ActionList.LinkItem href={COPILOT_SPACES_PATH} onClick={() => recordClick('SPACES')}>
            <ActionList.LeadingVisual>
              <SpacesIcon />
            </ActionList.LeadingVisual>
            Spaces
          </ActionList.LinkItem>

          {copilotFeatureFlags.taskOrientedAssistive && (
            <ActionList.Item
              onSelect={() => {
                recordClick('TASK_ORIENTED_ASSISTIVE')
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

        <ActionMenu onOpenChange={isOpen => isOpen && recordClick('IDE_MENU_OPEN')}>
          <ActionMenu.Anchor>
            <ActionList.Item onSelect={() => recordClick('OPEN_WITH')}>
              <ActionList.LeadingVisual>
                <DownloadIcon />
              </ActionList.LeadingVisual>
              Download for
            </ActionList.Item>
          </ActionMenu.Anchor>
          <ActionMenu.Overlay>
            <ActionList>
              <EditorMenuItems menuLocation={analyticsMenuLocation} mode={mode} />
              <ActionList.Divider />
              <ActionList.LinkItem
                href="https://docs.github.com/en/copilot/managing-copilot/configure-personal-settings/installing-github-copilot-in-the-cli"
                onClick={() => recordClick('CLI')}
              >
                CLI
                <ActionList.LeadingVisual>
                  <TerminalIcon />
                </ActionList.LeadingVisual>
              </ActionList.LinkItem>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>

        {copilotFeatureFlags.freeToPaidYourCopilotSettings ? (
          <YourCopilotButton />
        ) : (
          <ActionList.LinkItem href="/settings/copilot" onClick={() => recordClick('SETTINGS')}>
            Settings
            <ActionList.LeadingVisual>
              <GearIcon />
            </ActionList.LeadingVisual>
          </ActionList.LinkItem>
        )}
      </ActionList>
    </ActionMenu.Overlay>
  )
}
