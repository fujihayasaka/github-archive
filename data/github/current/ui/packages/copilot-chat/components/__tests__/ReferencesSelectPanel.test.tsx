import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {mockFetch} from '@github-ui/mock-fetch'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import React from 'react'

import {getCopilotChatProviderProps, getDefaultReducerState, getRepositoryMock} from '../../test-utils/mock-data'
import type {TopicItem} from '../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {MultistepReferencesSelectPanel, type SupportedReferenceType} from '../ReferencesSelectPanel'
// eslint-disable-next-line no-var
var searchValue = 'foo=bar'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  get ssrSafeLocation() {
    return {
      pathname: '/github/github/edit/main/README.md',
      search: searchValue,
      key: 'key',
      origin: 'https://github.com',
      hash: '',
      state: null,
    }
  },
}))

const mockRepo: TopicItem = {
  databaseId: 1,
  isInOrganization: true,
  nwo: 'github/github',
  ownerAvatarUrl: 'foo.com',
  ownerLogin: 'github',
  name: 'github',
}

jest.mock('../../hooks/use-repository-items', () => ({
  useRepositoryItems: () => ({repositories: [mockRepo], loading: false}),
}))

const useRepositoryFilesQueryMock = jest.fn()
jest.mock('../../hooks/use-repository-files-query', () => ({
  useRepositoryFilesQuery: () => useRepositoryFilesQueryMock(),
}))

jest.mock('../../hooks/use-filter-query', () => ({
  // mock useFilterQuery to return the items passed to it
  useFilterQuery: <T,>(items: T) => ({
    data: items,
    isLoading: false,
    isError: false,
    error: null,
  }),
}))

function renderTest(supportedReferenceTypes: SupportedReferenceType[]) {
  useRepositoryFilesQueryMock.mockReturnValue({
    data: {
      paths: ['/app/foo.txt'],
      directories: ['/app'],
    },
    isLoading: false,
    isError: false,
    error: null,
    status: 'success',
  })

  mockFetch.mockRoute(`/github-copilot/chat/repositories/${mockRepo.databaseId}`, getRepositoryMock(), {
    status: 200,
    ok: true,
  })

  mockFetch.mockRoute(
    `/search/suggestions?query=repo:github/github%20test`,
    {
      suggestions: [
        {
          kind: 'SUGGESTION_KIND_SYMBOL',
          symbol: {
            // eslint-disable-next-line camelcase
            fully_qualified_name: 'test-symbol',
          },
        },
      ],
    },
    {
      status: 200,
      ok: true,
    },
  )
  return renderRelay(
    () => (
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
        }}
      >
        <MultistepReferencesSelectPanel
          open
          onOpenChange={() => {}}
          cancelReturnFocusRef={React.createRef()}
          submitReturnFocusRef={React.createRef()}
          supportedReferenceTypes={supportedReferenceTypes}
        />
      </CopilotChatProvider>
    ),
    {
      relay: {
        queries: {},
      },
      wrapper: Wrapper,
    },
  )
}

let consoleSpy: jest.SpyInstance
describe('ReferencesSelectPanel', () => {
  beforeEach(() => {
    // Yes, we need to have this local storage auth token set in the tests.
    const provider = new CopilotAuthTokenProvider([])
    provider.setLocalStorageAuthToken(new AuthToken('buttercakes', 'whenever', []))
    setupResizeObserverMock()
    consoleSpy = jest.spyOn(console, 'error').mockImplementation()
  })

  afterEach(() => {
    consoleSpy.mockRestore()
  })

  test('by default renders files, folders, and symbols', async () => {
    const {user} = renderTest(['files', 'folders', 'symbols'])

    expect(await screen.findByText(/Choose a repository to browse for files, folders, and symbols/)).toBeInTheDocument()
    const menuItem = screen.getByRole('option', {name: /^github\/github/})
    await user.click(menuItem)

    expect(await screen.findByRole('option', {name: '/app/foo.txt'})).toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'test')
    expect(await screen.findByRole('option', {name: '/app'})).toBeInTheDocument()
    expect(await screen.findByRole('option', {name: 'test-symbol'})).toBeInTheDocument()
    expect(await screen.findByText(/Select files, folders, and symbols/)).toBeInTheDocument()
    // symbol search hits the search suggestions endpoint
    expect(mockFetch.fetch).toHaveBeenCalledWith(expect.stringContaining('/search/suggestions'), expect.any(Object))
  })

  test('renders only files and folders when symbols are disabled', async () => {
    const {user} = renderTest(['files', 'folders'])

    expect(await screen.findByText(/Choose a repository to browse for files and folders/)).toBeInTheDocument()
    const menuItem = screen.getByRole('option', {name: /^github\/github/})
    await user.click(menuItem)

    expect(await screen.findByRole('option', {name: '/app/foo.txt'})).toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'test')
    expect(await screen.findByRole('option', {name: '/app'})).toBeInTheDocument()
    expect(screen.queryByRole('option', {name: 'test-symbol'})).not.toBeInTheDocument()
    expect(await screen.findByText(/Select files and folders/)).toBeInTheDocument()
    // no symbol search should have happened
    expect(mockFetch.fetch).not.toHaveBeenCalledWith(expect.stringContaining('/search/suggestions'), expect.any(Object))
  })

  test('renders only files and symbols when folders are disabled', async () => {
    const {user} = renderTest(['files', 'symbols'])

    expect(await screen.findByText(/Choose a repository to browse for files and symbols/)).toBeInTheDocument()
    const menuItem = screen.getByRole('option', {name: /^github\/github/})
    await user.click(menuItem)

    expect(await screen.findByRole('option', {name: '/app/foo.txt'})).toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'test')
    expect(screen.queryByRole('option', {name: '/app'})).not.toBeInTheDocument()
    expect(await screen.findByRole('option', {name: 'test-symbol'})).toBeInTheDocument()
    expect(await screen.findByText(/Select files and symbols/)).toBeInTheDocument()
    // symbol search hits the search suggestions endpoint
    expect(mockFetch.fetch).toHaveBeenCalledWith(expect.stringContaining('/search/suggestions'), expect.any(Object))
  })

  test('renders only files when folders and symbols are disabled', async () => {
    const {user} = renderTest(['files'])

    expect(await screen.findByText(/Choose a repository to browse for files/)).toBeInTheDocument()
    const menuItem = screen.getByRole('option', {name: /^github\/github/})
    await user.click(menuItem)

    expect(await screen.findByRole('option', {name: '/app/foo.txt'})).toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'test')
    expect(screen.queryByRole('option', {name: '/app'})).not.toBeInTheDocument()
    expect(screen.queryByRole('option', {name: 'test-symbol'})).not.toBeInTheDocument()
    expect(await screen.findByText(/Select files/)).toBeInTheDocument()
    expect(mockFetch.fetch).not.toHaveBeenCalledWith(expect.stringContaining('/search/suggestions'), expect.any(Object))
  })

  test('renders only folders when files and symbols are disabled', async () => {
    const {user} = renderTest(['folders'])

    expect(await screen.findByText(/Choose a repository to browse for folders/)).toBeInTheDocument()
    const menuItem = screen.getByRole('option', {name: /^github\/github/})
    await user.click(menuItem)

    expect(screen.queryByRole('option', {name: '/app/foo.txt'})).not.toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'test')
    expect(await screen.findByRole('option', {name: '/app'})).toBeInTheDocument()
    expect(screen.queryByRole('option', {name: 'test-symbol'})).not.toBeInTheDocument()
    expect(await screen.findByText(/Select folders/)).toBeInTheDocument()
    expect(mockFetch.fetch).not.toHaveBeenCalledWith(expect.stringContaining('/search/suggestions'), expect.any(Object))
  })

  test('renders only symbols when files and folders are disabled', async () => {
    const {user} = renderTest(['symbols'])

    expect(await screen.findByText(/Choose a repository to browse for symbols/)).toBeInTheDocument()
    const menuItem = screen.getByRole('option', {name: /^github\/github/})
    await user.click(menuItem)

    expect(screen.queryByRole('option', {name: '/app/foo.txt'})).not.toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'test')
    expect(screen.queryByRole('option', {name: '/app'})).not.toBeInTheDocument()
    expect(await screen.findByRole('option', {name: 'test-symbol'})).toBeInTheDocument()
    expect(await screen.findByText(/Select symbols/)).toBeInTheDocument()
    expect(mockFetch.fetch).toHaveBeenCalledWith(expect.stringContaining('/search/suggestions'), expect.any(Object))
  })
})

function setupResizeObserverMock() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }

  Object.defineProperty(window, 'ResizeObserver', {
    writable: true,
    configurable: true,
    value: MockResizeObserver,
  })
}
