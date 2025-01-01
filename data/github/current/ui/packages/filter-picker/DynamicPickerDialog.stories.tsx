import {disableA11yRuleForDialog, storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {DynamicPickerDialog} from './DynamicPickerDialog'
import {fruitItemConfig, handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/FilterPicker/DynamicPickerDialog',
  component: DynamicPickerDialog,
  decorators: [storyWrapper()],
  args: {
    query: '',
    onSubmit: () => {},
    onDismiss: () => {},
    returnFocusRef: {current: null},
    description: 'What fruits do you like?',
    title: 'Filter your fruits',
    itemConfig: fruitItemConfig,
    providers: [],
  },
  parameters: {
    a11y: disableA11yRuleForDialog,
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof DynamicPickerDialog>

export default meta

type Story = StoryObj<typeof DynamicPickerDialog>

export const Default: Story = {}
