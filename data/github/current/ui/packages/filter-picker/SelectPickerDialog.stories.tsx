import {disableA11yRuleForDialog, storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {SelectPickerDialog} from './SelectPickerDialog'
import {fruitItemConfig, handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/FilterPicker/SelectPickerDialog',
  component: SelectPickerDialog,
  decorators: [storyWrapper()],
  args: {
    selected: [],
    onSubmit: () => {},
    onDismiss: () => {},
    returnFocusRef: {current: null},
    description: 'What fruits do you like?',
    itemConfig: fruitItemConfig,
    providers: [],
  },
  parameters: {
    a11y: disableA11yRuleForDialog,
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof SelectPickerDialog>

export default meta

type Story = StoryObj<typeof SelectPickerDialog>

export const SingleSelect: Story = {
  args: {
    selectionVariant: 'single',
    title: 'Select a fruit',
  },
}

export const MultiSelect: Story = {
  args: {
    selectionVariant: 'multiple',
    title: 'Select fruits',
  },
}
