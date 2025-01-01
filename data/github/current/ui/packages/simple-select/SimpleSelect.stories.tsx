import type {Meta} from '@storybook/react'
import {SimpleSelect, type SelectProps} from './SimpleSelect'

const meta = {
  title: 'Recipes/SimpleSelect',
  component: SimpleSelect,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    selectionVariant: {
      control: {
        type: 'select',
        options: ['single', 'multiple'],
      },
    },
    items: {
      control: {
        type: 'object',
      },
    },
    label: {
      control: {
        type: 'text',
      },
    },
    focusTarget: {
      control: {
        type: 'select',
        options: ['first-item', 'first-target'],
      },
    },
  },
} satisfies Meta<typeof SimpleSelect>

export default meta

const defaultArgs: Partial<SelectProps> = {
  items: [
    {label: 'Item 1', id: 'item-1', groupId: 1, selected: true},
    {label: 'Item 2', id: 'item-2', groupId: 1, selected: true},
    {label: 'Item 3', id: 'item-3', groupId: 2, selected: false},
    {label: 'Item 4', id: 'item-4', groupId: 2, selected: false},
    {label: 'Item 5', id: 'item-5', groupId: 3, selected: false},
    {label: 'Item 6', id: 'item-6', selected: false},
    {label: 'Item 7', id: 'item-7', selected: false},
  ],
  selectionVariant: 'multiple',
  label: 'Select an item',
}

export const Default = {
  args: {
    ...defaultArgs,
  },
  render: (args: SelectProps) => <SimpleSelect {...args} selectable={() => {}} />,
}
