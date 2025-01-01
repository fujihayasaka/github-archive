import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {getListSessionsRoutePayload} from '../test-utils/mock-data'
import {agentSessionsApp} from '../agent-sessions'
import type {ListSessionsResponse} from '../routes/list-sessions'

const server = setupServer()

function seedServer({mainQuery}: {mainQuery: ListSessionsResponse}) {
  server.use(
    http.get('/:owner/:repo/sessions', () => {
      return HttpResponse.json({
        payload: {
          listSessionsRoute: {
            mainQuery,
          },
        },
      })
    }),
  )
}

describe('list-sessions', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    server.resetHandlers()
  })
  afterAll(() => {
    server.close()
  })

  test('Renders the ListSessions', async () => {
    const mainQuery = getListSessionsRoutePayload()

    seedServer({mainQuery})
    render(agentSessionsApp, '/monalisa/smile/sessions', {appPayload: {}})

    expect(await screen.findByText(`Session ${mainQuery.sessions[0]!.id}`)).toBeInTheDocument()
  })
})
