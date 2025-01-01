import {ExperimentsDialog} from '@github-ui/copilot-chat/components/ExperimentsDialog'
import {PreviousThreadsHeaderMenu} from '@github-ui/copilot-chat/components/PreviousThreadsHeaderMenu'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {isRepository, threadName as getThreadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {DialogType} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {setTitle} from '@github-ui/document-metadata'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {PlusIcon} from '@primer/octicons-react'
import {Box, Heading, Label, LinkButton} from '@primer/react'

import {RepoButton} from './RepoButton'
import {ThreadHeaderMenu} from './ThreadHeaderMenu'

interface HeaderProps {
  staffDialogRef: React.MutableRefObject<HTMLDivElement | null>
  showStaffDialog: DialogType
  setShowStaffDialog: (value: DialogType) => void
}

export function Header(props: HeaderProps) {
  const {staffDialogRef, showStaffDialog, setShowStaffDialog} = props
  const state = useChatState()
  const manager = useChatManager()
  const {currentTopic, messages} = state
  const threadName = getThreadName(manager.getSelectedThread(state))
  setTitle(`${threadName} · GitHub Copilot`)
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  return messages.length > 0 || state.currentTopic ? (
    <Box
      sx={{
        alignItems: 'center',
        borderBottom: '1px solid',
        borderBottomColor: 'border.default',
        justifyContent: 'space-between',
        display: 'flex',
        px: 3,
        py: '12px',
      }}
    >
      <Heading as="h1" sx={{fontSize: 2, mr: 1}}>
        {threadName}
      </Heading>
      {messages.length > 0 && currentTopic && isRepository(currentTopic) && <RepoButton repo={currentTopic} />}
      <Box sx={{display: 'flex', alignItems: 'center', gap: 3, marginInlineStart: 'auto'}}>
        {state.renderBetaLabel && (lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>)}
        <Actions setShowStaffDialog={setShowStaffDialog} />
      </Box>
      {showStaffDialog === DialogType.Experiments && (
        <ExperimentsDialog
          onDismiss={() => {
            setShowStaffDialog(DialogType.None)
          }}
          experimentsDialogRef={staffDialogRef}
        />
      )}
    </Box>
  ) : null
}

interface ActionsProps {
  setShowStaffDialog: (value: DialogType) => void
}

function Actions(props: ActionsProps) {
  return (
    <Box sx={{alignItems: 'center', display: 'flex', flexShrink: 0, gap: 1}}>
      <LinkButton
        href="/copilot"
        leadingVisual={PlusIcon}
        sx={{
          mr: 1,
          '[data-component=text]': {display: ['none', 'block', 'block']}, // Hide the button text on the smallest screens
        }}
      >
        New conversation
      </LinkButton>
      <PreviousThreadsHeaderMenu />
      <ThreadHeaderMenu setShowStaffDialog={props.setShowStaffDialog} />
    </Box>
  )
}
