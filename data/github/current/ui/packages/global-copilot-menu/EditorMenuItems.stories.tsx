import {ActionList} from '@primer/react'
import type {Meta} from '@storybook/react'

import {EditorMenuItems, type EditorMenuItemsProps} from './EditorMenuItems'

export default {
  title: 'EditorMenuItems',
  component: EditorMenuItems,
} satisfies Meta<typeof EditorMenuItems>

const args: EditorMenuItemsProps = {
  menuLocation: 'storybook',
  mode: 'global_nav',
}

export const Default = () => (
  <ActionList>
    <EditorMenuItems {...args} />
  </ActionList>
)
