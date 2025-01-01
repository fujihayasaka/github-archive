import type {Meta} from '@storybook/react'
import {DefaultAssigneePickerAnchor} from './DefaultAssigneePickerAnchor'

type DefaultAssigneePickerAnchorProps = React.ComponentProps<typeof DefaultAssigneePickerAnchor>

const meta = {
  title: 'ItemPicker/DefaultAssigneePickerAnchor',
  component: DefaultAssigneePickerAnchor,
} satisfies Meta<DefaultAssigneePickerAnchorProps>

export default meta

const args = {
  assignees: [],
  readonly: false,
} satisfies DefaultAssigneePickerAnchorProps

export const Example = {args}

export const Readonly = {
  args: {...args, readonly: true},
}
