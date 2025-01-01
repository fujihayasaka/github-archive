import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {type ComponentProps, useState} from 'react'

import {CustomPropertyStringEditor} from './CustomPropertyStringEditor'

type StoryArgs = ComponentProps<typeof CustomPropertyStringEditor>

function Template(args: StoryArgs) {
  const {propertyValue, ...props} = args
  const [value, onChange] = useState(propertyValue || '')

  return <CustomPropertyStringEditor {...props} propertyValue={value} onChange={onChange} />
}

const meta: Meta<StoryArgs> = {
  title: 'Apps/Custom Properties/Components/Editors/CustomPropertyStringEditor',
  component: Template,
  decorators: [
    Story => (
      <Box sx={{width: 200}}>
        <Story />
      </Box>
    ),
  ],
  args: {
    propertyValue: 'ID-123.456',
    defaultValue: 'ID-000.000',
    orgName: 'properties-game',
  },
} satisfies Meta<typeof CustomPropertyStringEditor>

export default meta

type Story = StoryObj<typeof Template>

export const Default: Story = {}
export const Required: Story = {
  args: {
    propertyValue: undefined,
  },
}
export const Optional: Story = {
  args: {
    defaultValue: undefined,
  },
}
export const Mixed: Story = {
  args: {
    propertyValue: undefined,
    mixed: true,
  },
}

export const Truncation: Story = {
  args: {
    propertyValue: 'unbelievably-long-value-that-we-must-fit',
    defaultValue: 'unbelievably-long-default-value-that-we-must-fit',
  },
}
