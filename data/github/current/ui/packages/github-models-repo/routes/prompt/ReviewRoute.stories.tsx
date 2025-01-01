import type {Meta, StoryObj} from '@storybook/react'
import {HttpResponse, delay, http} from 'msw'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {repoModelsPath} from '@github-ui/paths'
import {ReviewRoute} from './ReviewRoute'
import {getReviewAppPayload, mockModels} from '../../test-utils/mock-data'

const appPayload = getReviewAppPayload()
const repo = appPayload.payload.repository
const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/pull/${appPayload.payload.pull.number}`

const meta = {
  title: 'Apps/GitHub Models repository/ReviewRoute',
  component: ReviewRoute,
  decorators: [storyWrapper({appPayload, pathname})],
  parameters: {
    msw: {
      handlers: [
        http.get(repoModelsPath({repo: appPayload.payload.repository}), async () => {
          await delay(1000)
          return HttpResponse.json(mockModels)
        }),
        http.get('/_side-panels/global', async () => {
          return HttpResponse.text('')
        }),
      ],
    },
  },
} satisfies Meta<typeof ReviewRoute>

export default meta

type Story = StoryObj<typeof ReviewRoute>

export const Example = {} satisfies Story
