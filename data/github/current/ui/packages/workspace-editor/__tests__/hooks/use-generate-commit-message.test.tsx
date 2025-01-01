// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import '../../test-utils/mocks'

import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {QueryClient} from '@github-ui/react-query'
// eslint-disable-next-line @github-ui/github-monorepo/prefer-github-ui-react-query, @github-ui/github-monorepo/no-query-client-provider
import {QueryClientProvider} from '@tanstack/react-query'
import {renderHook, waitFor} from '@testing-library/react'
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
import React from 'react'
import {Route, Routes} from 'react-router-dom'

import {App} from '../../App'
import {useGenerateCommitMessage} from '../../hooks/use-generate-commit-message'

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-helpers')
jest.mock('@github-ui/copilot-auth-token')
jest.mock('@github-ui/react-core/use-route-payload')

const queryClient = new QueryClient()
function getRouteWrapper(pathname: string) {
  const testRoute = jsonRoute({path: '/:owner/:repo/pull/:number/edit', Component: App})
  // eslint-disable-next-line react/display-name
  return ({children}: {children: React.ReactNode}) => (
    <QueryClientProvider client={queryClient}>
      <Wrapper pathname={pathname} routes={[testRoute]}>
        <Routes>
          <Route path={testRoute.path} element={children} />
        </Routes>
      </Wrapper>
    </QueryClientProvider>
  )
}

const mockedMakeCapiRequest = makeCAPIRequest as jest.Mock
const mockedRoutePayload = useRoutePayload as jest.Mock
describe('useGenerateCommitMessage', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it("does nothing when a user doesn't have permission", async () => {
    mockedRoutePayload.mockReturnValue({
      copilot: {apiURL: '', ssoOrganizations: []},
      copilotAccessAllowed: false,
    })
    const {result} = renderHook(
      () =>
        useGenerateCommitMessage({
          changedFiles: [],
        }),
      {wrapper: getRouteWrapper('/monalisa/smile/pull/1/edit')},
    )

    await waitFor(() => {
      expect(result.current).toEqual({generatedCommitMessage: null, isLoading: false})
    })
  })

  it('formats the arguments correctly', async () => {
    const changedFile = {
      patch: {
        hunks: [
          {
            oldStart: 1,
            newStart: 1,
            oldLines: 1,
            newLines: 1,
            lines: ['hello world', 'goodbye world'],
          },
        ],
      },
      path: 'greeting.md',
      status: undefined,
    }

    mockedMakeCapiRequest.mockResolvedValue({
      ok: true,
    })
    mockedRoutePayload.mockReturnValue({
      copilot: {apiURL: '', ssoOrganizations: []},
      copilotAccessAllowed: true,
    })
    renderHook(
      () =>
        useGenerateCommitMessage({
          changedFiles: [changedFile],
        }),
      {wrapper: getRouteWrapper('/monalisa/smile/pull/1/edit')},
    )

    await waitFor(() => {
      expect(mockedMakeCapiRequest).toHaveBeenCalledTimes(1)
    })

    await waitFor(() => {
      expect(mockedMakeCapiRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          body: {
            messages: [
              {
                role: 'user',
                content: '',
                copilot_references: [
                  {
                    type: 'github.diff-hunk',
                    data: {
                      type: 'diff-hunk',
                      changeReference: '',
                      fileName: 'greeting.md',
                      headerContext: '',
                      diff: expect.stringContaining('@@ -1,1 +1,1 @@\nhello world\ngoodbye world'),
                    },
                  },
                ],
              },
            ],
          },
        }),
      )
    })
  })
})
