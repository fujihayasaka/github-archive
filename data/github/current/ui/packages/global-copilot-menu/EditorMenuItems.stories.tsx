import {ActionList} from '@primer/react'
import {EditorMenuItems} from './EditorMenuItems'
import type {Meta} from '@storybook/react'

export default {
  title: 'EditorMenuItems',
  component: EditorMenuItems,
} satisfies Meta<typeof EditorMenuItems>

export const Default = () => (
  <ActionList>
    <EditorMenuItems />
  </ActionList>
)
