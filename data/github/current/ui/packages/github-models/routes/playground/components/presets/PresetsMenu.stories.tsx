import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {PresetsMenu} from './PresetsMenu'
import {HttpResponse, delay, http} from 'msw'
import {fn} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {mockModelDetails, mockPreset} from '../../__tests__/mocks'
import type {PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import type {PresetsPayload} from '../../../../types'
import {parametersConfig} from '../../../../utils/story-utils'

type StoryArgs = typeof PresetsMenu

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PresetsMenu',
  component: PresetsMenu,
  args: {
    modelDetails: mockModelDetails,
  },
  argTypes: {
    modelDetails: {control: {type: 'object'}},
  },
  parameters: {
    ...parametersConfig,
    msw: {
      handlers: [
        http.get('/marketplace/models/presets', async () => {
          await delay(1000)
          const preset2 = Object.assign({}, mockPreset, {
            name: 'Some Other Preset',
            conversationHistory: [],
            description: 'This is another excellent preset I have made.',
            parameters: {},
            private: false,
            urlIdentifier: `${mockPreset.urlIdentifier}-2`,
          })
          return HttpResponse.json({limit_per_user: 50, presets: [mockPreset, preset2]} as PresetsPayload)
        }),
      ],
    },
  },
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setModelState = fn()

      return (
        <Wrapper
          search={`?preset=${mockPreset.urlIdentifier}`}
          pathname={modelPlaygroundPath(mockModelDetails.catalogData)}
        >
          <PlaygroundManagerProvider manager={manager}>
            <Story />
          </PlaygroundManagerProvider>
        </Wrapper>
      )
    },
  ],
}
