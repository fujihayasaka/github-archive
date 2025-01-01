import type {PropertyValue} from '@github-ui/custom-properties-types'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {type ComponentProps, useState} from 'react'

import {multiSelectDefinition, requiredMultiSelectDefinition} from '../__tests__/test-helpers'
import {CustomPropertyMultiSelectPanel} from './CustomPropertyMultiSelectPanel'

type StoryArgs = ComponentProps<typeof CustomPropertyMultiSelectPanel>

function Template(args: StoryArgs) {
  const {propertyValue, ...props} = args
  const [value, onChange] = useState<PropertyValue>(propertyValue || [])
  const [mixed, changeMixed] = useState(args.mixed)

  return (
    <CustomPropertyMultiSelectPanel
      {...props}
      mixed={mixed}
      propertyValue={value as string[]}
      onChange={v => {
        onChange(v)
        changeMixed(false)
      }}
    />
  )
}

const meta: Meta<StoryArgs> = {
  title: 'Apps/Custom Properties/Components/Editors/CustomPropertyMultiSelectPanel',
  component: Template,
  decorators: [
    Story => (
      <Box sx={{width: 200}}>
        <Story />
      </Box>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof Template>

export const NonRequired: Story = {
  args: {
    ...multiSelectDefinition,
    mixed: false,
  },
}

export const MixedNonRequired: Story = {
  args: {
    ...multiSelectDefinition,
    mixed: true,
  },
}

export const Required: Story = {
  args: {
    ...requiredMultiSelectDefinition,
    mixed: false,
  },
}

export const MixedRequired: Story = {
  args: {
    ...requiredMultiSelectDefinition,
    mixed: true,
  },
}

const allowedValues = [
  'very_long_option_that_is_hard_to_fit',
  'another_very_long_option_that_is_hard_to_fit',
  'yet_one_more_very_long_option_that_is_hard_to_fit',
]

export const TruncatedNonRequired: Story = {
  args: {
    ...multiSelectDefinition,
    allowedValues,
    mixed: false,
  },
}

export const TruncatedRequired: Story = {
  args: {
    ...requiredMultiSelectDefinition,
    allowedValues,
    mixed: false,
  },
}
