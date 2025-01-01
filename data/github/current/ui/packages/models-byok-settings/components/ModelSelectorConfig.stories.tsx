import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {useState} from 'react'

import {mockSelectorModel} from '../test-utils/mocks'
import type {CustomModel} from '../types'
import {ModelSelectorConfig} from './ModelSelectorConfig'

export default {
  title: 'Apps/Models BYOK settings/Components/ModelSelectorConfig',
  component: ModelSelectorConfig,
  args: {
    model: mockSelectorModel({name: 'my-model-o1'}),
    selected: false,
    onSelect: fn(),
  },
  argTypes: {
    editable: {
      type: 'boolean',
    },
  },
  decorators: [
    Story => (
      <div style={{maxWidth: 437}} role="group">
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof ModelSelectorConfig>

type Story = StoryObj<typeof ModelSelectorConfig>

export const Default: Story = {}

export const Playground: Story = {
  args: {
    editable: true,
  },
  render(args) {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const [model, setModel] = useState(args.model)
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const [isSelected, setIsSelected] = useState(args.selected)

    return (
      <ModelSelectorConfig
        {...args}
        model={model}
        onSave={newValue => {
          setModel(m => {
            return Object.assign({}, m, {
              name: newValue.length ? newValue : undefined,
            } as CustomModel)
          })
        }}
        onSelect={setIsSelected}
        selected={isSelected}
      />
    )
  },
}

export const AsFresh: Story = {
  args: {
    model: mockSelectorModel({slug: 'my-model-o1', fresh: true}),
  },
}

export const AsEditable: Story = {
  args: {
    model: mockSelectorModel({slug: 'my-model-o1', fresh: true}),
    editable: true,
  },
}

export const AsDeprecated: Story = {
  args: {
    model: mockSelectorModel({slug: 'my-model-o1', deprecated: true}),
  },
}

export const AsCustomName: Story = {
  args: {
    model: mockSelectorModel({slug: 'my-model-o1'}),
  },
}

export const AsDeprecatedCustomName: Story = {
  args: {
    model: mockSelectorModel({slug: 'my-model-o1', name: 'My Model 🎉', deprecated: true}),
  },
}
