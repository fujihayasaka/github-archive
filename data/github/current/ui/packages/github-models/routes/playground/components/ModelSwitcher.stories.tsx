import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn, within} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import ModelSwitcher from './ModelSwitcher'
import {mockModel} from '../../playground/__tests__/mocks'
import {parametersConfig} from '../../../utils/story-utils'

const model2 = Object.assign({}, mockModel, {
  id: `${mockModel.id}-2`,
  name: 'model-2',
  friendly_name: 'Model 2',
})
const model3 = Object.assign({}, mockModel, {
  id: `${mockModel.id}-3`,
  name: 'model-3',
  friendly_name: 'Really Quite A Very Long Model Name You Would Not Believe',
})
const model4 = Object.assign({}, mockModel, {
  id: `${mockModel.id}-4`,
  name: 'model-4-o1-mini',
  friendly_name: 'An O1 Mini Model',
})

const meta: Meta<typeof ModelSwitcher> = {
  title: 'Apps/GitHub Models/ModelSwitcher',
  component: ModelSwitcher,
  args: {
    model: mockModel,
    onSelect: fn(),
    availableModels: [mockModel, model2, model3, model4],
    isLoadingModels: false,
  },
  argTypes: {
    model: {control: 'object'},
  },
  parameters: {
    ...parametersConfig,
  },
}

export default meta

type Story = StoryObj<typeof ModelSwitcher>

export const Example = {
  decorators: [
    Story => {
      return (
        <Wrapper pathname={modelPlaygroundPath(mockModel)}>
          <Story />
        </Wrapper>
      )
    },
  ],
} satisfies Story

export const Opened = {
  decorators: [
    Story => {
      return (
        <Wrapper pathname={modelPlaygroundPath(mockModel)}>
          <Story />
        </Wrapper>
      )
    },
  ],
  async play({canvasElement, step}) {
    const canvas = within(canvasElement)

    await step('Open the model switcher', async () => {
      const button = canvas.getByRole('button', {name: 'Switch model'})
      button.click()
    })
  },
} satisfies Story
