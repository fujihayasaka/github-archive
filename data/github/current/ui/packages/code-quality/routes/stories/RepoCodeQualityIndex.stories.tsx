import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'
import {RepoCodeQualityIndex} from '../RepoCodeQualityIndex'
import {codeQualityAppBuilder} from '../../config/app-builder'
import {repoCodeQualityIndexRoute} from '../repo-code-quality-index-route'
import {http, HttpResponse} from 'msw'
import {codeQualityRulesPath} from '@github-ui/paths'
import {repoCodeQualityIndexHandlers} from '../../__tests__/utils/handlers'
import {getRepoCodeQualityIndexRoutePayload} from '../../test-utils/mock-data'
import {Grade} from '../../types/grade'

const meta = {
  title: 'Apps/Code Quality/RepoCodeQualityIndex',
  component: RepoCodeQualityIndex,
  decorators: [dataRouterDecorator],
  parameters: {
    dataRouter: {
      app: codeQualityAppBuilder.createDataRouterAppFromRoutes([
        repoCodeQualityIndexRoute.toRoute({Component: RepoCodeQualityIndex}),
      ]),
      initialEntries: [
        repoCodeQualityIndexRoute.generatePath({
          owner: 'octodemo',
          repo: 'repo1',
        }),
      ],
    },
    msw: {
      handlers: repoCodeQualityIndexHandlers,
    },
  },
} satisfies DataRouterMeta<typeof RepoCodeQualityIndex>

export default meta

type MyComponentStory = DataRouterStoryObj<typeof RepoCodeQualityIndex>

export const Default: MyComponentStory = {}

export const ErrorGettingRules: MyComponentStory = {
  parameters: {
    msw: {
      handlers: [
        // Override the default handler for the error case
        http.get(codeQualityRulesPath({owner: 'octodemo', repo: 'repo1'}), () => {
          return HttpResponse.json({error: 'An error occurred'}, {status: 500})
        }),
        ...repoCodeQualityIndexHandlers,
      ],
    },
  },
}

export const NoFindings: MyComponentStory = {
  parameters: {
    msw: {
      handlers: [
        http.get(repoCodeQualityIndexRoute.generatePath({owner: 'octodemo', repo: 'repo1'}), () => {
          const response = {
            meta: {},
            payload: {
              [repoCodeQualityIndexRoute.id]: {
                ...getRepoCodeQualityIndexRoutePayload(),
                maintainability: {findingsCount: 0, grade: Grade.A},
                reliability: {findingsCount: 0, grade: Grade.A},
              },
            },
          }
          return HttpResponse.json(response)
        }),
      ],
    },
  },
}

export const Loading: MyComponentStory = {
  parameters: {
    msw: {
      handlers: [
        http.get(codeQualityRulesPath({owner: 'octodemo', repo: 'repo1'}), () => {
          return new Promise(() => {})
        }),
        ...repoCodeQualityIndexHandlers,
      ],
    },
  },
}
