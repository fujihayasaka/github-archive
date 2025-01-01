import {http, HttpResponse} from 'msw'
import {setupServer as setupMSWServer} from 'msw/node'
import {
  foundBranch,
  foundPullRequest,
  getCodeScanningDevelopmentSectionProps,
  queryToFind,
} from '../test-utils/mock-data'

const props = getCodeScanningDevelopmentSectionProps()

const handlers = [
  http.get(props.linkableItemsSearchPath, ({request}) => {
    const searchParams = new URL(request.url, window.location.origin).searchParams
    const query = searchParams.get('query') || ''

    const response = {
      results: [foundBranch, foundPullRequest].filter(result => {
        if (!query) {
          return true
        }
        return (
          (result.type === 'pull_request' && query === queryToFind.pull_request) ||
          (result.type === 'branch' && query === queryToFind.branch)
        )
      }),
    }
    return HttpResponse.json(response)
  }),
]

export function setupServer() {
  const server = setupMSWServer(...handlers)

  beforeAll(() => server.listen())
  afterEach(() => {
    server.resetHandlers()
  })
  afterAll(() => server.close())

  return {server}
}
