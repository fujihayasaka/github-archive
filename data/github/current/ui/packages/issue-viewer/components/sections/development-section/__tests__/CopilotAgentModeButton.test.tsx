import {act, screen, waitFor} from '@testing-library/react'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {renderRelay} from '@github-ui/relay-test-utils'
import {Suspense} from 'react'
import {CopilotAgentModeButton, type CopilotAgentModeButtonProps} from '../CopilotAgentModeButton'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {ThemeProvider} from '@primer/react'
import type {User} from '@github-ui/react-core/test-utils'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {Observable} from 'relay-runtime'

// Used to mock the ssrSafeWindow.open
jest.mock('@github-ui/ssr-utils', () => {
  const actual = jest.requireActual('@github-ui/ssr-utils')
  return {
    ...actual,
    ssrSafeWindow: {
      ...actual.ssrSafeWindow,
      open: jest.fn(),
    },
  }
})

// Used to mock the REST API request/response for the repository data in useCopilotAgent
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const mockVerifiedFetch = jest.mocked(verifiedFetch)

const repoA = buildRepository({owner: 'orgA', name: 'repoA'})
const repoB = buildRepository({owner: 'orgA', name: 'repoB'})
const repoC = buildRepository({owner: 'orgB', name: 'repoC'})

function setup({repo, issueId, onError}: Partial<CopilotAgentModeButtonProps>) {
  const {relayMockEnvironment, user} = renderRelay(
    () => {
      return (
        <ThemeProvider>
          <Suspense fallback="Loading...">
            <CopilotAgentModeButton
              repo={repo ?? {id: mockRelayId(), name: 'repoA', owner: {login: 'orgA'}}}
              issueId={issueId ?? 1}
              onError={onError ?? jest.fn()}
            />
          </Suspense>
        </ThemeProvider>
      )
    },
    {
      relay: {
        queries: {
          topRepositories: {
            type: 'preloaded',
            query: TopRepositories,
            variables: {topRepositoriesFirst: 10, hasIssuesEnabled: null, owner: null},
          },
        },
        mockResolvers: {
          RepositoryConnection() {
            return {
              edges: [{node: repoA}, {node: repoB}, {node: repoC}],
            }
          },
        },
      },
    },
  )
  return {environment: relayMockEnvironment, user}
}

const openRepositoryPicker = (user: User) => {
  const repoButton = screen.getByRole('button', {
    name: 'Select code repository',
  })

  user.click(repoButton)
}

test('renders repositories when user clicks on the dropdown button', async () => {
  const {user} = setup({
    repo: {id: repoA.id, name: 'repoA', owner: {login: 'orgA'}},
    issueId: 1,
    onError: jest.fn(),
  })

  openRepositoryPicker(user)

  const options = await screen.findAllByRole('option')

  expect(options).toHaveLength(3)
  expect(options[0]).toHaveTextContent('orgA/repoA')
})

test('opens a codespace with current repo when button is clicked', async () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const mockFetchQuery = jest.spyOn(require('relay-runtime'), 'fetchQuery')

  // Mock the useCopilotAgentDefaultBranchRepositoryQuery
  const mockResponse = {
    node: {
      __typename: 'Repository',
      databaseId: 123,
      defaultBranchRef: {
        name: 'main',
      },
    },
  }

  mockFetchQuery.mockImplementationOnce(() =>
    Observable.create(sink => {
      sink.next(mockResponse)
      sink.complete()
    }),
  )

  // Mock a successful response from the Codespaces Controller
  mockVerifiedFetch.mockResolvedValue(
    new Response(
      JSON.stringify({
        codespace_name: 'test-codespace',
      }),
      {
        status: 200,
        headers: {'Content-Type': 'application/json'},
      },
    ),
  )

  const assignMock = jest.fn()
  const newTabMock = {location: {assign: assignMock}}
  jest
    .spyOn(ssrSafeWindow as {open: (url?: string) => Window | null}, 'open')
    .mockReturnValue(newTabMock as unknown as Window)

  const {user} = setup({
    repo: {id: repoA.id, name: 'repoA', owner: {login: 'orgA'}},
    issueId: 1,
    onError: jest.fn(),
  })

  const button = await screen.findByText('Code with Copilot Agent Mode')
  await user.click(button)

  // Verify that ssrSafeWindow.open was called with a blank tab initially
  expect(ssrSafeWindow?.open).toHaveBeenCalledWith('about:blank')

  // Verify the fetchQuery call
  expect(mockFetchQuery).toHaveBeenCalledWith(expect.anything(), expect.anything(), {
    id: repoA.id,
  })

  // Verify a POST request was made to create the Codespace via verifiedFetch (in the useCopilotAgent hook)
  expect(mockVerifiedFetch).toHaveBeenCalledWith('/codespaces/', {
    method: 'POST',
    body: expect.any(FormData),
  })

  await waitFor(() => {
    expect(assignMock).toHaveBeenCalledWith('/codespaces/test-codespace')
  })
})

test('opens a codespace with a selected repo when the dropdown icon button is clicked', async () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const mockFetchQuery = jest.spyOn(require('relay-runtime'), 'fetchQuery')

  // Mock the useCopilotAgentDefaultBranchRepositoryQuery
  const mockResponse = {
    node: {
      __typename: 'Repository',
      databaseId: 123,
      defaultBranchRef: {
        name: 'main',
      },
    },
  }

  mockFetchQuery.mockImplementationOnce(() =>
    Observable.create(sink => {
      sink.next(mockResponse)
      sink.complete()
    }),
  )

  // Mock a successful response from the Codespaces Controller
  mockVerifiedFetch.mockResolvedValue(
    new Response(
      JSON.stringify({
        codespace_name: 'apple-scone-123',
      }),
      {
        status: 200,
        headers: {'Content-Type': 'application/json'},
      },
    ),
  )

  const assignMock = jest.fn()
  const newTabMock = {location: {assign: assignMock}}
  jest
    .spyOn(ssrSafeWindow as {open: (url?: string) => Window | null}, 'open')
    .mockReturnValue(newTabMock as unknown as Window)

  const {user} = setup({
    repo: {id: repoA.id, name: 'repoA', owner: {login: 'orgA'}},
    issueId: 1,
    onError: jest.fn(),
  })

  openRepositoryPicker(user)

  const options = await screen.findAllByRole('option')
  expect(options).toHaveLength(3)
  expect(options[1]).toHaveTextContent('orgA/repoB')

  act(() => {
    user.click(options[1]!)
  })

  await waitFor(() => {
    expect(mockFetchQuery).toHaveBeenCalledWith(expect.anything(), expect.anything(), {id: repoB.id})
  })

  // Verify a POST request was made to create the Codespace via verifiedFetch (in the useCopilotAgent hook)
  expect(mockVerifiedFetch).toHaveBeenCalledWith('/codespaces/', {
    method: 'POST',
    body: expect.any(FormData),
  })

  await waitFor(() => {
    expect(assignMock).toHaveBeenCalledWith('/codespaces/apple-scone-123')
  })
})

test('opens a codespace when the current repo is selected from the dropdown', async () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const mockFetchQuery = jest.spyOn(require('relay-runtime'), 'fetchQuery')

  // Mock the useCopilotAgentDefaultBranchRepositoryQuery
  const mockResponse = {
    node: {
      __typename: 'Repository',
      databaseId: 123,
      defaultBranchRef: {
        name: 'main',
      },
    },
  }

  mockFetchQuery.mockImplementationOnce(() =>
    Observable.create(sink => {
      sink.next(mockResponse)
      sink.complete()
    }),
  )

  // Mock a successful response from the Codespaces Controller
  mockVerifiedFetch.mockResolvedValue(
    new Response(
      JSON.stringify({
        codespace_name: 'everything-bagel-456',
      }),
      {
        status: 200,
        headers: {'Content-Type': 'application/json'},
      },
    ),
  )

  const assignMock = jest.fn()
  const newTabMock = {location: {assign: assignMock}}
  jest
    .spyOn(ssrSafeWindow as {open: (url?: string) => Window | null}, 'open')
    .mockReturnValue(newTabMock as unknown as Window)

  const {user} = setup({
    repo: {id: repoC.id, name: 'repoC', owner: {login: 'orgB'}},
    issueId: 1,
    onError: jest.fn(),
  })

  openRepositoryPicker(user)

  const options = await screen.findAllByRole('option')
  expect(options).toHaveLength(3)
  expect(options[2]).toHaveTextContent('orgB/repoC')

  act(() => {
    user.click(options[2]!)
  })

  await waitFor(() => {
    expect(mockFetchQuery).toHaveBeenCalledWith(expect.anything(), expect.anything(), {id: repoC.id})
  })

  // Verify a POST request was made to create the Codespace via verifiedFetch (in the useCopilotAgent hook)
  expect(mockVerifiedFetch).toHaveBeenCalledWith('/codespaces/', {
    method: 'POST',
    body: expect.any(FormData),
  })

  await waitFor(() => {
    expect(assignMock).toHaveBeenCalledWith('/codespaces/everything-bagel-456')
  })
})

test('closes tab upon error', async () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const mockFetchQuery = jest.spyOn(require('relay-runtime'), 'fetchQuery')

  // Mock the useCopilotAgentDefaultBranchRepositoryQuery
  const mockResponse = {
    node: {
      __typename: 'Repository',
      databaseId: 123,
      defaultBranchRef: {
        name: 'main',
      },
    },
  }

  mockFetchQuery.mockImplementationOnce(() =>
    Observable.create(sink => {
      sink.next(mockResponse)
      sink.complete()
    }),
  )

  // Mock a successful response from the Codespaces Controller
  mockVerifiedFetch.mockResolvedValue(
    new Response(
      JSON.stringify({
        error: 'Codespace creation failed. You have too many codespaces running. Please stop some and try again.',
        error_type: 'concurrency_limit_error',
      }),
      {
        status: 422,
        headers: {'Content-Type': 'application/json'},
      },
    ),
  )

  const closeMock = jest.fn()
  const newTabMock = {close: closeMock, location: {assign: jest.fn()}}
  jest
    .spyOn(ssrSafeWindow as {open: (url?: string) => Window | null}, 'open')
    .mockReturnValue(newTabMock as unknown as Window)

  const {user} = setup({
    repo: {id: repoA.id, name: 'repoA', owner: {login: 'orgA'}},
    issueId: 1,
    onError: jest.fn(),
  })

  const button = await screen.findByText('Code with Copilot Agent Mode')
  await user.click(button)

  // Verify that ssrSafeWindow.open was called with a blank tab initially
  expect(ssrSafeWindow?.open).toHaveBeenCalledWith('about:blank')

  // Verify the fetchQuery call
  expect(mockFetchQuery).toHaveBeenCalledWith(expect.anything(), expect.anything(), {
    id: repoA.id,
  })

  // Verify a POST request was made to create the Codespace via verifiedFetch (in the useCopilotAgent hook)
  expect(mockVerifiedFetch).toHaveBeenCalledWith('/codespaces/', {
    method: 'POST',
    body: expect.any(FormData),
  })

  expect(closeMock).toHaveBeenCalled()
})

function buildRepository({name, owner}: {name: string; owner: string}) {
  return {
    id: mockRelayId(),
    name,
    owner: {
      login: owner,
    },
    isPrivate: false,
    isArchived: false,
    __typename: 'Repository',
  }
}
