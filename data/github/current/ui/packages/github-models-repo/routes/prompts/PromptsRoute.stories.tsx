import type {Meta, StoryObj} from '@storybook/react'
import {HttpResponse, delay, http} from 'msw'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {repoModelsPath} from '@github-ui/paths'
import {PromptsRoute} from './PromptsRoute'
import {getModelRepoPromptsAppPayload, getModelRepoPromptsRoutePayload, mockModels} from '../../test-utils/mock-data'

const appPayload = Object.assign(getModelRepoPromptsAppPayload(), {
  ['enabled_features']: {['github_models_repo_playground']: true},
})
const routePayload = getModelRepoPromptsRoutePayload()
const pathname = `/${appPayload.repository.ownerLogin}/${appPayload.repository.name}/models/prompts`

const meta = {
  title: 'Apps/GitHub Models repository/PromptsRoute',
  component: PromptsRoute,
  decorators: [storyWrapper({appPayload, pathname, routePayload})],
  parameters: {
    msw: {
      handlers: [
        http.get(repoModelsPath({repo: appPayload.repository}), async () => {
          await delay(1000)
          return HttpResponse.json(mockModels)
        }),
      ],
    },
  },
} satisfies Meta<typeof PromptsRoute>

export default meta

type Story = StoryObj<typeof PromptsRoute>

export const Example = {} satisfies Story
