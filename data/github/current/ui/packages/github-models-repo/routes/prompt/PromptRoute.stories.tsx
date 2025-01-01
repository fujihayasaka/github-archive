import type {Meta, StoryObj} from '@storybook/react'
import {HttpResponse, delay, http} from 'msw'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {repoModelsPath, repoModelsPromptPath} from '@github-ui/paths'
import {PromptRoute} from './PromptRoute'
import {getPromptAppPayload, mockModels} from '../../test-utils/mock-data'

const appPayload = getPromptAppPayload()
const pathname = repoModelsPromptPath({repo: appPayload.payload.repository, action: 'new'})

const meta = {
  title: 'Apps/GitHub Models repository/PromptRoute',
  component: PromptRoute,
  decorators: [storyWrapper({appPayload, pathname})],
  parameters: {
    msw: {
      handlers: [
        http.get(repoModelsPath({repo: appPayload.payload.repository}), async () => {
          await delay(1000)
          return HttpResponse.json(mockModels)
        }),
      ],
    },
  },
} satisfies Meta<typeof PromptRoute>

export default meta

type Story = StoryObj<typeof PromptRoute>

export const Example = {} satisfies Story
