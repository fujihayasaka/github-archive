import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ButtonGroup, IconButton, LinkButton} from '@primer/react'

import styles from './EditorMenu.module.css'
import {EditorMenuItems, recordMenuClick} from './EditorMenuItems'
import editors from './editors'

export interface EditorMenuProps {
  menuLocation: string
  mode: string
  onButtonClick?: () => void
}

export function EditorMenu({menuLocation, mode, onButtonClick}: EditorMenuProps) {
  const handleClick = (eventName: string, action: string) => {
    if (copilotFeatureFlags.freeToPaidTelemetry) {
      recordMenuClick({eventName, menuLocation, mode, action})
    } else {
      sendEvent('dotcom_chat.activate', {
        target: `EDITOR_UPSELL_BANNER_${eventName.toUpperCase()}`,
        mode,
      })
    }
  }

  return (
    <ButtonGroup className={styles.actions}>
      <LinkButton
        className={styles.editorButton}
        href={editors.vscode.url}
        leadingVisual={<img src={editors.vscode.icon} alt="" height="20" width="20" />}
        onClick={() => {
          onButtonClick?.()
          handleClick('vscode', 'ide_menu_primary_button_click')
        }}
      >
        {editors.vscode.name}
      </LinkButton>
      <ActionMenu>
        <ActionMenu.Anchor>
          {/* Tooltip breaks ButtonGroup: https://github.com/primer/react/issues/4129 */}
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            aria-label="More editors"
            icon={TriangleDownIcon}
            unsafeDisableTooltip
            onClick={() => {
              handleClick('menu', 'ide_menu_open')
            }}
            data-testid="editor-dropdown-button"
          />
        </ActionMenu.Anchor>

        <ActionMenu.Overlay align="end">
          <ActionList>
            <EditorMenuItems menuLocation={menuLocation} mode={mode} onItemClick={onButtonClick} />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </ButtonGroup>
  )
}
