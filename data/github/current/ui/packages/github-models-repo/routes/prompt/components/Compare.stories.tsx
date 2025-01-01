import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {repoModelsPromptPath} from '@github-ui/paths'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {type PromptCompareManager, PromptCompareManagerContext} from '../prompt-compare-manager'
import {PromptCompareStateProvider} from '../contexts/PromptCompareStateContext'
import {ModelsProvider} from '../contexts/ModelsContext'
import {Compare} from './Compare'
import {getPromptAppPayload, mockModels, mockPromptCompareState} from '../../../test-utils/mock-data'

const appPayload = getPromptAppPayload()
const pathname = repoModelsPromptPath({repo: appPayload.payload.repository, action: 'new'})

const meta = {
  title: 'Apps/GitHub Models repository/Compare',
  component: Compare,
  decorators: [
    storyWrapper({appPayload, pathname}),
    Story => (
      <CurrentRepositoryProvider repository={appPayload.payload.repository}>
        <ModelsProvider models={mockModels}>
          <PromptCompareStateProvider state={mockPromptCompareState()}>
            <PromptCompareManagerContext.Provider value={{} as PromptCompareManager}>
              <Story />
            </PromptCompareManagerContext.Provider>
          </PromptCompareStateProvider>
        </ModelsProvider>
      </CurrentRepositoryProvider>
    ),
  ],
} satisfies Meta<typeof Compare>

export default meta

type Story = StoryObj<typeof Compare>

export const Example = {} satisfies Story
