import {ChevronDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import type {Meta} from '@storybook/react'
import {MockFileDiffReference} from '../../__tests__/__utils__/mock-data'
import {CopilotDiffChatContextMenu} from './CopilotDiffChatContextMenu'

const StoryComponent = () => (
  <ActionMenu>
    <ActionMenu.Button trailingVisual={ChevronDownIcon}>Example Menu</ActionMenu.Button>

    <ActionMenu.Overlay width="medium">
      <ActionList>
        <CopilotDiffChatContextMenu fileDiffReference={MockFileDiffReference} />
      </ActionList>
    </ActionMenu.Overlay>
  </ActionMenu>
)

const meta = {
  title: 'Apps/Copilot/Diff Chat/CopilotDiffChatContextMenu',
  component: StoryComponent,
} satisfies Meta<typeof CopilotDiffChatContextMenu>

export default meta

export const Example = {
  name: 'CopilotDiffChatContextMenu',
}
