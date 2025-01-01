import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {HttpResponse, delay, http} from 'msw'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import ModelSwitcher from './ModelSwitcher'
import {mockModel} from '../../playground/__tests__/mocks'
import {PlaygroundManagerContext, type PlaygroundManager} from '../../../utils/playground-manager'
import type {Model} from '@github-ui/marketplace-common'
import {parametersConfig} from '../../../utils/story-utils'

const meta: Meta<typeof ModelSwitcher> = {
  title: 'Apps/GitHub Models/ModelSwitcher',
  component: ModelSwitcher,
  args: {
    model: mockModel,
    canUseO1Models: true,
    onSelect: fn(),
  },
  argTypes: {
    model: {control: 'object'},
    canUseO1Models: {control: {type: 'boolean'}},
  },
  parameters: {
    ...parametersConfig,
    msw: {
      handlers: [
        http.get('/marketplace/models', async () => {
          await delay(1000)
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
          return HttpResponse.json([mockModel, model2, model3, model4] as Model[])
        }),
      ],
    },
  },
}

export default meta

type Story = StoryObj<typeof ModelSwitcher>

export const Example: Story = {
  render: args => <ModelSwitcher {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.getSideModel = fn()
      return (
        <Wrapper pathname={ModelUrlHelper.playgroundUrl(mockModel)}>
          <PlaygroundManagerContext.Provider value={manager}>
            <Story />
          </PlaygroundManagerContext.Provider>
        </Wrapper>
      )
    },
  ],
}
