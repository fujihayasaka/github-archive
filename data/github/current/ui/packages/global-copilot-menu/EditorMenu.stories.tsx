import {ActionList} from '@primer/react'
import type {Meta} from '@storybook/react'

import {EditorMenu, type EditorMenuProps} from './EditorMenu'

export default {
  title: 'EditorMenu',
  component: EditorMenu,
} satisfies Meta<typeof EditorMenu>

const args: EditorMenuProps = {
  menuLocation: 'storybook',
  mode: 'global_nav',
}

export const Default = () => (
  <ActionList>
    <EditorMenu {...args} />
  </ActionList>
)
Default.parameters = {
  a11y: {
    test: 'todo',
  },
}
