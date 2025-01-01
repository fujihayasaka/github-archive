import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {CopilotIcon} from '@primer/octicons-react'

import {copilotChatPanelID} from '../utils/constants'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

const FloatingButton = () => {
  const state = useChatState()
  const manager = useChatManager()
  const thread = manager.getSelectedThread(state)

  return (
    <IconButtonWithTooltip
      // This is a floating button and should not be tabbable.
      // It should be accessible via the floating button hotkey.
      // Keyboard navigation is supported for the static button in the header.
      tabIndex={-1}
      id="copilot-floating-button"
      icon={CopilotIcon}
      label="Open Copilot chat"
      aria-controls={copilotChatPanelID}
      tooltipDirection="w"
      onClick={() => {
        void manager.openChat(thread, state.currentView, 'floating-button-v2', state.chatVisibleSettingPath)
      }}
      sx={{
        '--floating-button-size': '2.5rem',
        position: 'fixed',
        bottom: 3,
        right: 3,
        zIndex: 9,
        color: 'fg.default !important',
        bg: 'var(--bgColor-default, var(--color-canvas-default))',
        borderRadius: 'var(--floating-button-size)',
        border: 'none',
        boxShadow: 'var(--shadow-floating-small)',
        height: 'var(--floating-button-size)',
        width: 'var(--floating-button-size)',
        '&:focus, &:active': {
          boxShadow: 'var(--shadow-floating-small, var(--shadow-small))',
        },
      }}
      data-hotkey="Shift+Z"
    />
  )
}

export default FloatingButton
