import type {Meta, StoryObj} from '@storybook/react'
import {HttpResponse, delay, http} from 'msw'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {repoModelPlaygroundPath, repoModelsPath} from '@github-ui/paths'
import {PlaygroundRoute} from './PlaygroundRoute'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {mockModel, mockModels} from '../../test-utils/mock-data'

const appPayload = {repository: createRepository()}
const model = mockModel()
const pathname = repoModelPlaygroundPath(appPayload.repository, model)

const meta = {
  title: 'Apps/GitHub Models repository/PlaygroundRoute',
  component: PlaygroundRoute,
  decorators: [storyWrapper({appPayload, pathname})],
  parameters: {
    msw: {
      handlers: [
        http.get(repoModelsPath({repo: appPayload.repository}), async () => {
          await delay(1000)
          return HttpResponse.json(mockModels.concat([model]))
        }),
      ],
    },
  },
} satisfies Meta<typeof PlaygroundRoute>

export default meta

type Story = StoryObj<typeof PlaygroundRoute>

export const Example = {} satisfies Story
