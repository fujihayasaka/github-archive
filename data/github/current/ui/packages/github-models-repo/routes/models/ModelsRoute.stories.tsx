import type {Meta, StoryObj} from '@storybook/react'
import {HttpResponse, delay, http} from 'msw'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {repoModelsPath} from '@github-ui/paths'
import {ModelsRoute} from './ModelsRoute'
import {getModelsRoutePayload, mockModels} from '../../test-utils/mock-data'
import {mockGettingStarted} from './components/__tests__/mocks'

const appPayload = Object.assign(getModelsRoutePayload(), {
  ['enabled_features']: {['github_models_repo_playground']: true},
})
const pathname = `/${appPayload.repository.ownerLogin}/${appPayload.repository.name}/models`
const firstModel = mockModels[0]!

const meta = {
  title: 'Apps/GitHub Models repository/ModelsRoute',
  component: ModelsRoute,
  parameters: {
    msw: {
      handlers: [
        http.get(repoModelsPath({repo: appPayload.repository}), async () => {
          await delay(1000)
          return HttpResponse.json(mockModels)
        }),
        http.get(
          `${repoModelsPath({repo: appPayload.repository})}/${firstModel.registry}/${firstModel.name}`,
          async () => {
            await delay(1000)
            return HttpResponse.json({gettingStarted: mockGettingStarted()})
          },
        ),
      ],
    },
  },
} satisfies Meta<typeof ModelsRoute>

export default meta

type Story = StoryObj<typeof ModelsRoute>

export const Example = {
  render: () => {
    return (
      <Wrapper appPayload={appPayload} pathname={pathname}>
        <ModelsRoute />
      </Wrapper>
    )
  },
} satisfies Story
