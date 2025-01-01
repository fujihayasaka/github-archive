import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {SelectPickerDialog} from './SelectPickerDialog'
import {SingleSelectPicker} from './SingleSelectPicker'
import {fruitItemConfig, handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/FilterPicker/SingleSelectPicker',
  component: SingleSelectPicker,
  decorators: [storyWrapper()],
  args: {
    itemConfig: fruitItemConfig,
    renderDialog: ({onDismiss, returnFocusRef}) => (
      <SelectPickerDialog
        onDismiss={onDismiss}
        returnFocusRef={returnFocusRef}
        selectionVariant="single"
        onSubmit={() => {}}
        title="Select you favorite fruit"
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
} satisfies Meta<typeof SingleSelectPicker>

export default meta

type Story = StoryObj<typeof SingleSelectPicker>

export const Default: Story = {}
