import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'
import {codeQualityAppBuilder} from '../../config/app-builder'
import {RepoCodeQualityShow} from '../RepoCodeQualityShow'
import {repoCodeQualityShowRoute} from '../repo-code-quality-show-route'
import {codeQualityRuleFindingsPath} from '@github-ui/paths'
import {http, HttpResponse} from 'msw'
import {repoCodeQualityShowHandlers} from '../../__tests__/utils/handlers'
import {getRepoCodeQualityShowRoutePayload} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Code Quality/RepoCodeQualityShow',
  component: RepoCodeQualityShow,
  decorators: [dataRouterDecorator],
  parameters: {
    dataRouter: {
      app: codeQualityAppBuilder.createDataRouterAppFromRoutes([
        repoCodeQualityShowRoute.toRoute({Component: RepoCodeQualityShow}),
      ]),
      initialEntries: [
        repoCodeQualityShowRoute.generatePath({
          owner: 'octodemo',
          repo: 'repo1',
          rule_id: 'foo',
        }),
      ],
    },
    msw: {handlers: repoCodeQualityShowHandlers},
  },
} satisfies DataRouterMeta<typeof RepoCodeQualityShow>

export default meta

type MyComponentStory = DataRouterStoryObj<typeof RepoCodeQualityShow>

export const Default: MyComponentStory = {}

export const Error: MyComponentStory = {
  parameters: {
    msw: {
      handlers: [
        // Override the default handler for the error case
        http.get(codeQualityRuleFindingsPath({owner: 'octodemo', repo: 'repo1', ruleId: 'foo'}), () => {
          return HttpResponse.json({error: 'An error occurred'}, {status: 500})
        }),
        ...repoCodeQualityShowHandlers,
      ],
    },
  },
}

export const NoFindings: MyComponentStory = {
  parameters: {
    msw: {
      handlers: [
        http.get(repoCodeQualityShowRoute.generatePath({owner: 'octodemo', repo: 'repo1', rule_id: 'foo'}), () => {
          const response = {
            meta: {},
            payload: {
              [repoCodeQualityShowRoute.id]: {...getRepoCodeQualityShowRoutePayload(), fileCount: 0},
            },
          }
          return HttpResponse.json(response)
        }),
      ],
    },
  },
}

export const FindingsLoading: MyComponentStory = {
  parameters: {
    msw: {
      handlers: [
        http.get(codeQualityRuleFindingsPath({owner: 'octodemo', repo: 'repo1', ruleId: 'foo'}), () => {
          return new Promise(() => {})
        }),
        ...repoCodeQualityShowHandlers,
      ],
    },
  },
}
