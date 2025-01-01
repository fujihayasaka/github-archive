import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {MultiSelectPicker} from './MultiSelectPicker'
import {SelectPickerDialog} from './SelectPickerDialog'
import {fruitItemConfig, handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/FilterPicker/MultiSelectPicker',
  component: MultiSelectPicker,
  decorators: [storyWrapper()],
  args: {
    itemConfig: fruitItemConfig,
    renderDialog: ({onDismiss, returnFocusRef}) => (
      <SelectPickerDialog
        onDismiss={onDismiss}
        returnFocusRef={returnFocusRef}
        selectionVariant="multiple"
        onSubmit={() => {}}
        title="Select your fruits"
        itemConfig={fruitItemConfig}
        providers={[]}
      />
    ),
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof MultiSelectPicker>

export default meta

type Story = StoryObj<typeof MultiSelectPicker>

export const Default: Story = {}
