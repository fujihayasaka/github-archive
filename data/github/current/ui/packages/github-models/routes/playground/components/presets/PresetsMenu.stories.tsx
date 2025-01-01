import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {PresetsMenu} from './PresetsMenu'
import {HttpResponse, delay, http} from 'msw'
import {fn, within, expect} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {mockModelDetails, mockPreset} from '../../__tests__/mocks'
import type {PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import type {PresetsPayload} from '../../../../types'
import {parametersConfig} from '../../../../utils/story-utils'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {mockModelState} from '../__tests__/mocks'

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
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setModelState = fn()

      return (
        <Wrapper
          search={`?preset=${mockPreset.urlIdentifier}`}
          pathname={modelPlaygroundPath(mockModelDetails.catalogData)}
        >
          <PlaygroundStateProvider state={{models: [mockModelState()], syncInputs: false}}>
            <PlaygroundManagerProvider manager={manager}>
              <Story />
            </PlaygroundManagerProvider>
          </PlaygroundStateProvider>
        </Wrapper>
      )
    },
  ],
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

export const Example = {} satisfies Story

export const Interaction = {
  async play({canvasElement, step}) {
    const canvas = within(canvasElement)

    await step('Open the presets menu', async () => {
      const presetsMenuButton = canvas.getByRole('button', {name: /Preset: \w/i})
      presetsMenuButton.click()
    })

    await step('Select a preset', async () => {
      await delay(1000)
      const presetItem = await canvas.findByRole('menuitemradio', {name: /Some Other Preset/i})
      presetItem.click()
    })

    await step('Verify the preset is selected', async () => {
      const presetsMenuButton = await canvas.findByRole('button', {name: /Preset: Some Other Preset/i})
      expect(presetsMenuButton).toBeVisible()
    })
  },
} satisfies Story
