import {GearIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {clsx} from 'clsx'

import {DiffCompactLinesPopover} from './components/DiffCompactLinesPopover'
import {DiffLinePresentationToggles} from './components/DiffLinePresentationToggles'
import {DiffViewPreferenceToggle} from './components/DiffViewPreferenceToggle'
import {DiffCommentsPreferenceToggle} from './components/DiffCommentsPreferenceToggle'

export type DiffViewSettingsProps = {
  invisible?: boolean
  lineSpacingPreferenceAvailable?: boolean
  reloadOnSplitPreferenceChange?: boolean
  reloadOnWhitespaceChange?: boolean
  small?: boolean
}

export function DiffViewSettings({
  invisible = true,
  lineSpacingPreferenceAvailable = true,
  reloadOnSplitPreferenceChange = false,
  reloadOnWhitespaceChange = false,
  small,
}: DiffViewSettingsProps) {
  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <button
            className={clsx(
              'Button Button--iconOnly',
              invisible ? 'Button--invisible' : 'Button--secondary',
              small && 'Button--small',
            )}
            aria-label="Open diff view settings"
          >
            <GearIcon />
          </button>
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            <DiffViewPreferenceToggle reloadOnChange={reloadOnSplitPreferenceChange} />
            <DiffCommentsPreferenceToggle />
            <ActionList.Divider />
            <DiffLinePresentationToggles
              lineSpacingPreferenceAvailable={lineSpacingPreferenceAvailable}
              reloadOnChange={reloadOnWhitespaceChange}
            />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <DiffCompactLinesPopover />
    </>
  )
}
