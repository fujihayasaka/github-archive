import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {mockFetch} from '@github-ui/mock-fetch'
import {type User, Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {SafeHTMLString} from '@github-ui/safe-html'
import safeStorage from '@github-ui/safe-storage'
import {screen, waitFor, within} from '@testing-library/react'

import {getCopilotChatProviderProps, getDefaultReducerState} from '../../test-utils/mock-data'
import type {Docset} from '../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {Chat} from '../Chat'
// eslint-disable-next-line no-var
var searchValue = 'foo=bar'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

const makeDocset = (props: Partial<Docset> = {}): Docset => {
  return {
    id: '1',
    name: 'test',
    ownerID: 1,
    ownerType: 'user',
    visibility: 'private',
    repos: ['foo/bar', 'baz/qux'],
    sourceRepos: [
      {
        id: 1,
        ownerID: 1,
        paths: [],
      },
      {
        id: 2,
        ownerID: 1,
        paths: [],
      },
    ],
    description: 'test description',
    createdByID: 1,
    ownerLogin: 'testUser',
    visibleOutsideOrg: false,
    iconHtml: '' as SafeHTMLString,
    avatarUrl: '',
    adminableByUser: false,
    protectedOrganizations: [],
    canChat: true,
    ...props,
  }
}

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

const adminableCopilotEnterpriseOrg = {
  id: '1',
  name: 'microsoft',
  login: 'microsoft',
  avatarUrl: 'foo.com',
}

describe('attach knowledge', () => {
  beforeEach(() => {
    const provider = new CopilotAuthTokenProvider([])
    provider.setLocalStorageAuthToken(new AuthToken('buttercakes', 'whenever', []))
  })

  test('menu items show up correctly', async () => {
    setupResizeObserverMock()
    const consoleSpy = jest.spyOn(console, 'error').mockImplementation()
    const knowledgeBases = [
      makeDocset({
        id: '1',
        ownerType: 'Organization',
        ownerID: 42,
        name: 'GitHub Docs Name',
        ownerLogin: 'github',
        repos: ['doesnt/matter'],
        description: 'GitHub Docs description',
      }),
      makeDocset({
        avatarUrl: '',
        id: '2',
        ownerType: 'Organization',
        ownerID: 42,
        name: 'Other Docs Name',
        ownerLogin: 'github',
        repos: ['doesnt/matter'],
        description: 'Other Docs description',
      }),
      makeDocset({
        avatarUrl: '',
        id: '3',
        ownerType: 'Organization',
        ownerID: 55,
        name: 'Jest docs',
        ownerLogin: 'jest',
        repos: ['doesnt/matter'],
        description: 'Jest description',
      }),
    ]

    mockFetch.mockRoute(
      '/github-copilot/docs/docsets',
      {knowledgeBases, administratedCopilotEnterpriseOrganizations: []},
      {
        status: 200,
        ok: true,
      },
    )
    const {user} = renderRelay(
      () => (
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            topicLoading: {state: 'loaded', error: null},
            messagesLoading: {state: 'loaded', error: null},
            ssoOrganizations: [{id: '1', login: 'microsoft', avatarUrl: 'foo.com'}],
            knowledgeBasesLoading: {state: 'pending', error: null},
            renderKnowledgeBases: true,
          }}
        >
          <Chat />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await openAttachKnowledgePanel(user)

    // would be good to getByRole('dialog') but apparently testing library doesn't recognize <dialog> elements
    const attachKnowledgeDialog = await screen.findByRole('dialog')
    // would also be good to getByRole('group') but testing library doesn't recognize <ul> elements as groups
    const ghHeader = await within(attachKnowledgeDialog).findByRole('heading', {name: 'github'})
    expect(ghHeader).toBeInTheDocument()

    expect(screen.getByTestId('knowledge-select-panel')).toBeInTheDocument()
    // we don't control the rendering here but we want to make sure items are grouped correctly
    // eslint-disable-next-line testing-library/no-node-access
    const ghGroup = ghHeader.parentElement!
    expect(await within(ghGroup).findByText(/GitHub Docs Name/)).toBeInTheDocument()
    expect(await within(ghGroup).findByText(/GitHub Docs description/)).toBeInTheDocument()
    expect(await within(ghGroup).findByText(/Other Docs Name/)).toBeInTheDocument()
    expect(await within(ghGroup).findByText(/Other Docs description/)).toBeInTheDocument()

    // would also be good to getByRole('group') but testing library doesn't recognize <ul> elements as groups
    // eslint-disable-next-line testing-library/no-node-access
    const jestGroup = (await within(attachKnowledgeDialog).findByRole('heading', {name: 'jest'})).parentElement!
    expect(await within(jestGroup).findByText(/Jest docs/)).toBeInTheDocument()
    expect(await within(jestGroup).findByText(/Jest description/)).toBeInTheDocument()

    // ensure sso org shows up
    expect(await screen.findByText(/Single sign-on to see content from microsoft/)).toBeInTheDocument()

    consoleSpy.mockRestore()
  }, 10000)

  test('shows empty picker with no button if renderKnowledgeBases is toggled off', async () => {
    setupResizeObserverMock()
    const knowledgeBases = [
      makeDocset({
        id: '1',
        ownerType: 'Organization',
        ownerID: 42,
        name: 'GitHub Docs Name',
        ownerLogin: 'github',
        repos: ['doesnt/matter'],
        description: 'GitHub Docs description',
      }),
    ]

    mockFetch.mockRoute(
      '/github-copilot/docs/docsets',
      {knowledgeBases, administratedCopilotEnterpriseOrganizations: []},
      {
        status: 200,
        ok: true,
      },
    )
    renderRelay(
      () => (
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            topicLoading: {state: 'loaded', error: null},
            messagesLoading: {state: 'loaded', error: null},
            ssoOrganizations: [{id: '1', login: 'microsoft', avatarUrl: 'foo.com'}],
            knowledgeBasesLoading: {state: 'pending', error: null},
          }}
        >
          <Chat />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(await screen.findByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByTestId('create-knowledge-base-button')).not.toBeInTheDocument()
    expect(screen.queryByTestId('create-knowledge-base-dropdown')).not.toBeInTheDocument()
  }, 10000)

  test('shows empty picker with no button if user has no adminable Copilot Enterprise orgs and no KBs', async () => {
    setupResizeObserverMock()
    mockFetch.mockRoute(
      '/github-copilot/docs/docsets',
      {knowledgeBases: [], administratedCopilotEnterpriseOrganizations: []},
      {status: 200, ok: true},
    )

    const {user} = renderRelay(
      () => (
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            topicLoading: {state: 'loaded', error: null},
            messagesLoading: {state: 'loaded', error: null},
            knowledgeBasesLoading: {state: 'loaded', error: null},
            renderKnowledgeBases: true,
          }}
        >
          <Chat />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await openAttachKnowledgePanel(user)

    expect(await screen.findByTestId('ask-admin-for-knowledge-base')).toBeInTheDocument()
    expect(screen.queryByTestId('knowledge-select-panel')).not.toBeInTheDocument()
    expect(screen.queryByTestId('create-knowledge-base-button')).not.toBeInTheDocument()
    expect(screen.queryByTestId('create-knowledge-base-dropdown')).not.toBeInTheDocument()
  }, 10000)

  test('shows empty picker with single button if user has just one adminable Copilot Enterprise org and no KBs', async () => {
    setupResizeObserverMock()
    mockFetch.mockRoute(
      '/github-copilot/docs/docsets',
      {knowledgeBases: [], administratedCopilotEnterpriseOrganizations: [adminableCopilotEnterpriseOrg]},
      {status: 200, ok: true},
    )
    const {user} = renderRelay(
      () => (
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            topicLoading: {state: 'loaded', error: null},
            messagesLoading: {state: 'loaded', error: null},
            knowledgeBasesLoading: {state: 'loaded', error: null},
            renderKnowledgeBases: true,
          }}
        >
          <Chat />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await openAttachKnowledgePanel(user)

    expect(await screen.findByTestId('create-knowledge-base-button')).toBeInTheDocument()
    expect(screen.queryByTestId('knowledge-select-panel')).not.toBeInTheDocument()
    expect(screen.queryByTestId('create-knowledge-base-dropdown')).not.toBeInTheDocument()
    expect(screen.queryByTestId('ask-admin-for-knowledge-base')).not.toBeInTheDocument()
  }, 10000)

  test('shows empty picker with multiple buttons if user has multiple adminable Copilot Enterprise orgs and no KBs', async () => {
    setupResizeObserverMock()
    mockFetch.mockRoute(
      '/github-copilot/docs/docsets',
      {
        knowledgeBases: [],
        administratedCopilotEnterpriseOrganizations: [
          adminableCopilotEnterpriseOrg,
          {...adminableCopilotEnterpriseOrg, id: '2'},
        ],
      },
      {status: 200, ok: true},
    )

    const {user} = renderRelay(
      () => (
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            topicLoading: {state: 'loaded', error: null},
            messagesLoading: {state: 'loaded', error: null},
            knowledgeBasesLoading: {state: 'loaded', error: null},
            renderKnowledgeBases: true,
          }}
        >
          <Chat />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await openAttachKnowledgePanel(user)

    expect(await screen.findByTestId('create-knowledge-base-dropdown')).toBeInTheDocument()
    expect(screen.queryByTestId('knowledge-select-panel')).not.toBeInTheDocument()
    expect(screen.queryByTestId('ask-admin-for-knowledge-base')).not.toBeInTheDocument()
    expect(screen.queryByTestId('create-knowledge-base-button')).not.toBeInTheDocument()
  }, 10000)
})

test('menu items show up correctly', async () => {
  setupResizeObserverMock()
  const safeLocalStorage = safeStorage('localStorage')
  safeLocalStorage.setItem('lastUsedKnowledgeBaseId', '2')
  safeLocalStorage.setItem('lastUsedKnowledgeBaseOrg', 'jest')

  const knowledgeBases = [
    makeDocset({
      id: '1',
      ownerType: 'Organization',
      ownerID: 42,
      name: 'GitHub Docs Name',
      ownerLogin: 'github',
      repos: ['doesnt/matter'],
      description: 'GitHub Docs description',
    }),
    makeDocset({
      avatarUrl: '',
      id: '2',
      ownerType: 'Organization',
      ownerID: 55,
      name: 'Other Docs Name',
      ownerLogin: 'jest',
      repos: ['doesnt/matter'],
      description: 'Other Docs description',
    }),
    makeDocset({
      avatarUrl: '',
      id: '3',
      ownerType: 'Organization',
      ownerID: 42,
      name: 'Jest docs',
      ownerLogin: 'github',
      repos: ['doesnt/matter'],
      description: 'Jest description',
    }),
  ]

  mockFetch.mockRoute(
    '/github-copilot/docs/docsets',
    {knowledgeBases, administratedCopilotEnterpriseOrganizations: []},
    {
      status: 200,
      ok: true,
    },
  )
  const {user} = renderRelay(
    () => (
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
          ssoOrganizations: [{id: '1', login: 'microsoft', avatarUrl: 'foo.com'}],
          knowledgeBasesLoading: {state: 'pending', error: null},
          renderKnowledgeBases: true,
        }}
      >
        <Chat />
      </CopilotChatProvider>
    ),
    {
      relay: {
        queries: {},
      },
      wrapper: Wrapper,
    },
  )

  await openAttachKnowledgePanel(user)

  await waitFor(() => expect(screen.queryByText('Fetching knowledge bases…')).not.toBeInTheDocument())

  const kbList = screen.getByRole('dialog')
  const kbItems = within(kbList).getAllByRole('option')

  expect(kbItems).toHaveLength(3)

  const firstKb = kbItems?.[0]

  expect(firstKb?.textContent).toContain('Other Docs description')
}, 10000)

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

async function openAttachKnowledgePanel(user: User) {
  const menuButton = screen.getByRole('button', {name: /^Attach/})
  await user.click(menuButton)
  const menuItem = screen.getByRole('menuitem', {name: /^Knowledge base/})
  await user.click(menuItem)
}
