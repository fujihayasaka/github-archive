import {act, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {getSessionRoutePayload, getFailedSessionRoutePayload} from '../test-utils/mock-data'
import {agentSessionsApp} from '../agent-sessions'
import type {SessionResponse} from '../routes/session'

const server = setupServer()

function seedServer({mainQuery}: {mainQuery: SessionResponse}) {
  let fetchCount = 0

  server.use(
    http.get('/:owner/:repo/pull/:id/agent-sessions/:sessionId', () => {
      fetchCount++
      return HttpResponse.json({
        payload: {
          sessionRoute: mainQuery,
        },
      })
    }),
    // Add proxy endpoint handler for logs
    http.get('/:owner/:repo/pull/:id/agent-sessions/proxy/:sessionId', () => {
      fetchCount++
      return HttpResponse.json({
        result: [
          // Direct array of LogEntry objects
          {
            id: 'mock-log-1',
            choices: [
              {
                finish_reason: 'stop',
                delta: {
                  content: 'Hello',
                  role: 'assistant',
                },
              },
            ],
          },
        ],
      })
    }),
    // Add token endpoint handler
    http.post('/:owner/:repo/pull/:number/agent-sessions/token', () => {
      fetchCount++
      return HttpResponse.json({
        token: 'test-token',
        expires_at: new Date(Date.now() + 3600 * 1000).toISOString(), // 1 hour from now
        refresh_at: new Date(Date.now() + 1800 * 1000).toISOString(), // 30 mins from now
        sso_org_ids: [],
      })
    }),
    // Add CAPI endpoint handler for sessions
    http.get('https://api.githubcopilot.com/agents/sessions/resource/pull/:pullId', () => {
      fetchCount++
      return HttpResponse.json({
        sessions: mainQuery.sessions,
        status: 'success',
      })
    }),
    // Mock CAPI endpoint for logs
    // TO DO: Replace mocked json with a stream
    http.get('https://api.githubcopilot.com/agents/sessions/:sessionId/logs', () => {
      fetchCount++
      return HttpResponse.json({
        result: [],
        status: 'success',
      })
    }),
  )
  return {fetchCount: () => fetchCount}
}

describe('sessions', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    server.resetHandlers()
  })
  afterAll(() => {
    server.close()
  })

  test('Renders the Session component (with focused session)', async () => {
    const mainQuery = getSessionRoutePayload()

    seedServer({mainQuery})
    render(agentSessionsApp, `/monalisa/smile/pull/1/agent-sessions/${mainQuery.activeSessionId}`, {appPayload: {}})

    expect(await screen.findByText(`Back to pull request`)).toBeInTheDocument()
  })

  test('Polls CAPI directly to fetch session data', async () => {
    const mainQuery = getSessionRoutePayload()

    const payloadWithoutMockData = {
      ...mainQuery,
      useMockData: false,
    }

    const {fetchCount} = seedServer({mainQuery: payloadWithoutMockData})

    render(agentSessionsApp, `/monalisa/smile/pull/1/agent-sessions/${mainQuery.activeSessionId}`, {
      appPayload: {},
    })

    await screen.findByText('Back to pull request')

    const initialFetchCount = fetchCount()
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 1500))
    })
    expect(fetchCount()).toBeGreaterThan(initialFetchCount)
  })

  test('Uses available mock data in development', async () => {
    const mainQuery = getSessionRoutePayload()
    const {fetchCount} = seedServer({
      mainQuery: {
        ...mainQuery,
        useMockData: true,
      },
    })

    render(agentSessionsApp, `/monalisa/smile/pull/1/agent-sessions/${mainQuery.activeSessionId}`, {
      appPayload: {},
    })

    await screen.findByText('Back to pull request')

    const initialFetchCount = fetchCount()
    await waitFor(
      () => {
        expect(fetchCount()).toEqual(initialFetchCount)
      },
      {timeout: 1500},
    )
  })

  test('Displays error message for failed session', async () => {
    const mainQuery = getFailedSessionRoutePayload()
    seedServer({
      mainQuery: {
        ...mainQuery,
        useMockData: false,
      },
    })

    render(agentSessionsApp, `/monalisa/smile/pull/1/agent-sessions/${mainQuery.activeSessionId}`, {
      appPayload: {},
    })

    const errorMessage = await screen.findByText('Copilot stopped work due to an error')
    expect(errorMessage).toBeInTheDocument()
  })
})
