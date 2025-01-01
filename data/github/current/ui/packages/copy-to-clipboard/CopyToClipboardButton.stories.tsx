import type {Meta} from '@storybook/react'
import {CopyToClipboardButton, type CopyToClipboardButtonProps} from './CopyToClipboardButton'

const meta = {
  title: 'Recipes/CopyToClipboardButton',
  component: CopyToClipboardButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    textToCopy: {control: 'text', defaultValue: 'Hello, Storybook!'},
  },
} satisfies Meta<typeof CopyToClipboardButton>

export default meta

const defaultArgs: Partial<CopyToClipboardButtonProps> = {
  textToCopy: 'Hello, Storybook!',
}

export const Default = {
  args: {
    ...defaultArgs,
  },
  render: (args: CopyToClipboardButtonProps) => <CopyToClipboardButton {...args} />,
}

export const Disabled = {
  args: {
    ...defaultArgs,
    disabled: true,
  },
  render: (args: CopyToClipboardButtonProps) => <CopyToClipboardButton {...args} />,
}
