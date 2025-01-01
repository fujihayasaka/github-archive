import {GearIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'

import {DiffCompactLinesPopover} from './components/DiffCompactLinesPopover'
import {DiffLinePresentationToggles} from './components/DiffLinePresentationToggles'
import {DiffViewPreferenceToggle} from './components/DiffViewPreferenceToggle'

export type DiffViewSettingsProps = {
  lineSpacingPreferenceAvailable?: boolean
  reloadOnChange?: boolean
}

export function DiffViewSettings({
  lineSpacingPreferenceAvailable = true,
  reloadOnChange = false,
}: DiffViewSettingsProps) {
  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <button className="Button Button--iconOnly Button--invisible" aria-label="Open diff view settings">
            <GearIcon />
          </button>
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            <DiffViewPreferenceToggle reloadOnChange={reloadOnChange} />
            <ActionList.Divider />
            <DiffLinePresentationToggles
              lineSpacingPreferenceAvailable={lineSpacingPreferenceAvailable}
              reloadOnChange={reloadOnChange}
            />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <DiffCompactLinesPopover />
    </>
  )
}
