import {ChevronDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import type {Meta} from '@storybook/react'
import {MockFileDiffReference} from '../../__tests__/__utils__/mock-data'
import {CopilotDiffChatBlobActionsMenuItems} from './CopilotDiffChatBlobActionsMenuItems'

const StoryComponent = () => (
  <ActionMenu>
    <ActionMenu.Button trailingVisual={ChevronDownIcon}>Example Menu</ActionMenu.Button>

    <ActionMenu.Overlay width="medium">
      <ActionList>
        <CopilotDiffChatBlobActionsMenuItems copilotChatReference={MockFileDiffReference} />
      </ActionList>
    </ActionMenu.Overlay>
  </ActionMenu>
)

const meta = {
  title: 'Apps/Copilot/Diff Chat/CopilotDiffChatBlobActionsMenuItems',
  component: StoryComponent,
} satisfies Meta<typeof CopilotDiffChatBlobActionsMenuItems>

export default meta

export const Example = {
  name: 'CopilotDiffChatBlobActionsMenuItems',
}
