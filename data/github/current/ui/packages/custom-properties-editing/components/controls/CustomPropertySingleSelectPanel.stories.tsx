import type {PropertyValue} from '@github-ui/custom-properties-types'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {type ComponentProps, useState} from 'react'

import {requiredSingleSelectDefinition, singleSelectDefinition} from '../__tests__/test-helpers'
import {CustomPropertySingleSelectPanel} from './CustomPropertySingleSelectPanel'

type StoryArgs = ComponentProps<typeof CustomPropertySingleSelectPanel>

function Template(args: StoryArgs) {
  const {propertyValue, ...props} = args
  const [value, onChange] = useState<PropertyValue>(propertyValue || '')
  const [mixed, changeMixed] = useState(args.mixed)

  return (
    <CustomPropertySingleSelectPanel
      {...props}
      mixed={mixed}
      propertyValue={value as string}
      onChange={v => {
        onChange(v)
        changeMixed(false)
      }}
    />
  )
}

const meta: Meta<StoryArgs> = {
  title: 'Apps/Custom Properties/Components/Editors/CustomPropertySingleSelectPanel',
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
    ...singleSelectDefinition,
    mixed: false,
  },
}

export const MixedNonRequired: Story = {
  args: {
    ...singleSelectDefinition,
    mixed: true,
  },
}

export const Required: Story = {
  args: {
    ...requiredSingleSelectDefinition,
    mixed: false,
  },
}

export const MixedRequired: Story = {
  args: {
    ...requiredSingleSelectDefinition,
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
    ...singleSelectDefinition,
    allowedValues,
    mixed: false,
  },
}

export const TruncatedRequired: Story = {
  args: {
    ...requiredSingleSelectDefinition,
    allowedValues,
    mixed: false,
  },
}
