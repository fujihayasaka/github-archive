import type {PropertyValue} from '@github-ui/custom-properties-types'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {type ComponentProps, useState} from 'react'

import {optionalBooleanDefinition, requiredBooleanDefinition} from '../__tests__/test-helpers'
import {CustomPropertyBooleanSelectPanel} from './CustomPropertyBooleanSelectPanel'

type StoryArgs = ComponentProps<typeof CustomPropertyBooleanSelectPanel>

function Template(args: StoryArgs) {
  const {propertyValue, ...props} = args
  const [value, onChange] = useState<PropertyValue>(propertyValue || '')
  const [mixed, changeMixed] = useState(args.mixed)

  return (
    <CustomPropertyBooleanSelectPanel
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
  title: 'Apps/Custom Properties/Components/Editors/CustomPropertyBooleanSelectPanel',
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
    ...optionalBooleanDefinition,
    mixed: false,
  },
}

export const MixedNonRequired: Story = {
  args: {
    ...optionalBooleanDefinition,
    mixed: true,
  },
}

export const Required: Story = {
  args: {
    ...requiredBooleanDefinition,
    mixed: false,
  },
}

export const MixedRequired: Story = {
  args: {
    ...requiredBooleanDefinition,
    mixed: true,
  },
}
