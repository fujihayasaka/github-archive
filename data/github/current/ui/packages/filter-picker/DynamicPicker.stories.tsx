import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {DynamicPicker} from './DynamicPicker'
import {DynamicPickerDialog} from './DynamicPickerDialog'
import {fruitItemConfig, handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/FilterPicker/DynamicPicker',
  component: DynamicPicker,
  decorators: [storyWrapper()],
  args: {
    query: '',
    renderDialog: ({onDismiss, returnFocusRef}) => (
      <DynamicPickerDialog
        onDismiss={onDismiss}
        returnFocusRef={returnFocusRef}
        onSubmit={() => {}}
        description="What fruits do you like?"
        title="Filter your fruits"
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
} satisfies Meta<typeof DynamicPicker>

export default meta

type Story = StoryObj<typeof DynamicPicker>

export const Default: Story = {}
