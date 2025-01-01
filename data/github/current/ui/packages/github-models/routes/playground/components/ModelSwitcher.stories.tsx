import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {HttpResponse, delay, http} from 'msw'
import ModelSwitcher from './ModelSwitcher'
import {mockModel} from '../../playground/__tests__/mocks'
import type {Model} from '@github-ui/marketplace-common'
import {parametersConfig} from '../../../utils/story-utils'

const meta: Meta<typeof ModelSwitcher> = {
  title: 'Apps/GitHub Models/ModelSwitcher',
  component: ModelSwitcher,
  args: {
    model: mockModel,
    onSelect: fn(),
  },
  argTypes: {
    model: {control: 'object'},
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
      return (
        <Wrapper pathname={modelPlaygroundPath(mockModel)}>
          <Story />
        </Wrapper>
      )
    },
  ],
}
