import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {UseThisModelButton} from './UseThisModelButton'
import {parametersConfig} from '../utils/story-utils'
import {mockModel} from '../routes/playground/__tests__/mocks'

type StoryArgs = typeof UseThisModelButton
type Story = StoryObj<StoryArgs>

const meta = {
  title: 'Apps/GitHub Models/UseThisModelButton',
  component: UseThisModelButton,
  parameters: {
    ...parametersConfig,
    viewport: {
      ...parametersConfig.viewport,
      viewports: {
        ...parametersConfig.viewport.viewports,
        tiny: {name: 'tiny', styles: {width: '300px', height: '300px'}},
      },
    },
  },
  args: {
    model: mockModel,
    variant: 'primary',
    onClick: fn(),
    block: false,
  },
  argTypes: {
    model: {control: 'object'},
    variant: {control: 'radio', options: ['primary', 'default', 'danger', 'invisible', 'link']},
    onClick: {control: false},
    block: {control: 'boolean'},
    tabIndex: {control: 'number'},
  },
} satisfies Meta<StoryArgs>

export default meta

export const Example: Story = {
  render: args => <UseThisModelButton {...args} />,
}
