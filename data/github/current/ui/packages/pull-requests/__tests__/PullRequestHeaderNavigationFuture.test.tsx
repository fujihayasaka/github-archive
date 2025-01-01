import {render as testRender} from '@github-ui/react-core/future/test-utils/render'
import {screen, within} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'
import {PullRequestHeaderNavigation} from '../components/PullRequestHeaderNavigation'
import {pullRequestsAppBuilder} from '../config/app-builder'
import {getAppPayload} from '../test-utils/app-mock-data'
import {getCommitsPageData} from '../test-utils/commits/commits-mock-data'
import {getHeaderPageData} from '../test-utils/header-mock-data'
import type {ReactElement} from 'react'
import type {CommitsRoutePayload, LayoutRoutePayload} from '../routes/route-payload-types'
import {pullRequestsLayoutRoute} from '../routes/layout-route'

const server = setupServer()

function render(element: ReactElement, data: SeedServerOptions) {
  seedServer(data)
  const routes = [
    pullRequestsLayoutRoute.toRoute({
      element,
    }),
  ]

  const appPayload = getAppPayload()
  const path = '/monalisa/smile/pull/1'
  return testRender(pullRequestsAppBuilder.createDataRouterAppFromRoutes(routes), path, {
    appPayload,
  })
}

type SeedServerOptions = {
  commitsRoutePayload?: CommitsRoutePayload
  layoutRoutePayload?: LayoutRoutePayload
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

function seedServer({
  commitsRoutePayload = getCommitsPageData(),
  layoutRoutePayload = getHeaderPageData(),
  labelCountPayload,
}: SeedServerOptions) {
  server.use(
    http.get('/:owner/:repo/pull/:pr_number/commits', () => {
      const payload = {
        pullRequestsLayoutRoute: layoutRoutePayload,
        pullRequestsCommitsRoute: commitsRoutePayload,
      }
      const meta = {title: 'PR Commits page'}

      return HttpResponse.json({
        payload,
        meta,
      })
    }),
    http.get('/:owner/:repo/pull/:pr_number', () => {
      return HttpResponse.json({
        payload: {
          pullRequestsLayoutRoute: layoutRoutePayload,
        },
        meta: {},
      })
    }),
    http.get('/:owner/:repo/pull/:pr_number/page_data/tab_counts', () => {
      if (labelCountPayload instanceof HttpResponse) return labelCountPayload
      return HttpResponse.json(labelCountPayload)
    }),
  )
}
