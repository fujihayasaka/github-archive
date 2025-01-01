import {render as testRender} from '@github-ui/react-core/future/test-utils/render'
import {screen, within} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'
import {PullRequestHeaderNavigation} from '../components/PullRequestHeaderNavigation'
import {pullRequestsAppBuilder} from '../config/app-builder'
import {pullRequestsCommitsRoute} from '../routes/commits-route'
import {getAppPayload} from '../test-utils/app-mock-data'
import {getCommitsRoutePayload} from '../test-utils/commits-mock-data'
import {getHeaderPageData} from '../test-utils/header-mock-data'
import type {ReactElement} from 'react'
import type {CommitsRoutePayload} from '../routes/Commits'

const server = setupServer()

function render(element: ReactElement, data: SeedServerOptions) {
  seedServer(data)
  return testRender(
    pullRequestsAppBuilder.createDataRouterAppFromRoutes([
      pullRequestsCommitsRoute.toRoute({
        element,
      }),
    ]),
    '/monalisa/smile/pull/1/commits',
    {
      appPayload: getAppPayload(),
    },
  )
}

type SeedServerOptions = {
  commitsRoutePayload?: CommitsRoutePayload
  labelCountPayload:
    | {conversationCount: number; checksCount: number; filesChangedCount: number}
    | HttpResponse
    | Response
}

describe('PullRequestHeaderNavigation (data router)', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    server.resetHandlers()
  })
  afterAll(() => {
    server.close()
  })
  test('renders nav with correct links', async () => {
    const {urls} = getHeaderPageData()
    const labelCountPayload = {
      conversationCount: 23423423,
      checksCount: 4,
      filesChangedCount: 5,
    }

    render(<PullRequestHeaderNavigation commitsCount={3} urls={urls} />, {labelCountPayload})

    const conversationTab = await screen.findByRole('tab', {name: /Conversation/i})
    expect(conversationTab).toHaveAttribute('href', urls.conversation)
    expect(conversationTab).toHaveTextContent(`${labelCountPayload.conversationCount}`)

    const commitsTab = screen.getByRole('tab', {name: /Commits/i})
    expect(commitsTab).toHaveAttribute('href', urls.commits)
    expect(commitsTab).toHaveTextContent('3')

    const checksTab = screen.getByRole('tab', {name: /Checks/i})
    expect(checksTab).toHaveAttribute('href', urls.checks)
    expect(checksTab).toHaveTextContent(`${labelCountPayload.checksCount}`)

    const filesTab = screen.getByRole('tab', {name: /Files/i})
    expect(filesTab).toHaveAttribute('href', urls.files)
    expect(filesTab).toHaveTextContent(`${labelCountPayload.filesChangedCount}`)
  })

  test('does not render the conversation, commit, checks, and files changed count if the data is not retrieved', async () => {
    const {urls} = getHeaderPageData()

    render(<PullRequestHeaderNavigation commitsCount={undefined} urls={urls} />, {
      labelCountPayload: HttpResponse.error(),
    })

    const conversationTab = await screen.findByRole('tab', {name: /Conversation/i})
    expect(conversationTab).toHaveAttribute('href', urls.conversation)
    // make sure tab does not have a span element in it
    expect(within(conversationTab).queryByRole('span')).not.toBeInTheDocument()

    const commitsTab = screen.getByRole('tab', {name: /Commits/i})
    expect(commitsTab).toHaveAttribute('href', urls.commits)
    // make sure tab does not have a span element in it
    expect(within(commitsTab).queryByRole('span')).not.toBeInTheDocument()

    const checksTab = screen.getByRole('tab', {name: /Checks/i})
    expect(checksTab).toHaveAttribute('href', urls.checks)
    // make sure tab does not have a span element in it
    expect(within(checksTab).queryByRole('span')).not.toBeInTheDocument()

    const filesTab = screen.getByRole('tab', {name: /Files/i})
    expect(filesTab).toHaveAttribute('href', urls.files)
    // make sure tab does not have a span element in it
    expect(within(filesTab).queryByRole('span')).not.toBeInTheDocument()
  })
})

function seedServer({commitsRoutePayload = getCommitsRoutePayload(), labelCountPayload}: SeedServerOptions) {
  server.use(
    http.get('/:owner/:repo/pull/:pr_number/commits', () => {
      return HttpResponse.json({
        payload: {
          pullRequestsCommitsRoute: {
            mainQuery: commitsRoutePayload,
          },
        },
      })
    }),
    http.get('/:owner/:repo/pull/:pr_number/page_data/tab_counts', () => {
      if (labelCountPayload instanceof HttpResponse) return labelCountPayload
      return HttpResponse.json(labelCountPayload)
    }),
  )
}
