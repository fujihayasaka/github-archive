// This test suite tests end to end experiences of the immersive copilot chat
// Entire stack is tested, with mocked fetch responses

import {mockResponses} from '@github-ui/copilot-chat/test-utils/mock-interactive'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {commitCreateIssueMutation} from '@github-ui/issue-create/mutations/create-issue-mutation'
import {IssueViewerViewGraphqlQuery} from '@github-ui/issue-viewer/IssueViewer'
import {IssueViewerSecondaryGraphqlQuery} from '@github-ui/issue-viewer/IssueViewerSecondaryView'
import {buildRepository} from '@github-ui/item-picker/test-utils/RepositoryPickerHelpers'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen, waitFor, waitForElementToBeRemoved, within} from '@testing-library/react'

import {CopilotImmersiveNoRelay} from '../../routes/CopilotImmersive'

// The import mocks have to be in test file due to jest behaviors (e.g. hoisting)
jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  // Allows safe-storage module to use local storage
  ssrSafeWindow: window,
  // Provides the current page location to useRouteThreadId
  // Provides empty hash prop to getHighlightedEventText in the issue rendering
  ssrSafeLocation: {origin: 'https://github.localhost', pathname: '/copilot/c/123', hash: ''},
}))

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useLocation: jest.fn(() => ({
    origin: 'https://github.localhost',
    pathname: '/copilot/c/123',
  })),
}))

jest.mock('@github-ui/issue-create/mutations/create-issue-mutation')
const createIssueMutationMock = jest.mocked(commitCreateIssueMutation)

beforeEach(() => {
  jest.spyOn(copilotFeatureFlags, 'immersiveIssuePreview', 'get').mockReturnValue(true)
})

test('Rendering and saving issue draft using chat confirmations', async () => {
  const fetches = [
    {
      // Immersive chat loads all threads
      request: {url: '/github/chat/threads?', method: 'GET'},
      response: {
        threads: [
          {
            id: '123',
            name: 'Thread Name',
            repoID: 0,
            repoOwnerID: 0,
            associatedRepoIDs: [],
            updatedAt: new Date().toString(),
          },
        ],
      },
    },
    {
      request: {url: '/github/chat/threads/123/messages', method: 'GET'},
      response: {
        thread: {id: '123'},
        messages: [
          {
            id: '1',
            parentMessageID: 'root',
            role: 'user',
            content: 'Create an issue',
            threadID: '123',
          },
          {
            id: '2',
            parentMessageID: '1',
            role: 'assistant',
            content:
              'I have drafted the issue.\n' +
              '````yaml type="draft-issue"\n' +
              'tag: "rename-dashboard-to-start"\n' +
              'repository: "github/repo1"\n' +
              'title: "Test title"\n' +
              'description: |\n' +
              '  Test description\n' +
              '````',
            threadID: '123',
            confirmations: [],
          },
        ],
      },
    },
  ]

  let fetchCount = 0
  mockResponses(fetches, () => fetchCount++)
  const {user} = renderRelay(() => <CopilotImmersiveNoRelay />, {
    relay: {
      queries: {
        // For our create issue form the names here don't really matter, as long as we register enough queries for mockResolvers to resolve
        query1: {
          type: 'lazy',
        },
        query2: {
          type: 'lazy',
        },
      },
      mockResolvers: {
        // For lazy queries, order is important here, we need to mock these in the order that they get called by repo picker
        // Note that below function names match the (type) names in
        // RepositoryPickerTopRepositoriesQuery and RepositoryPickerRepository typescript files
        // The files are hidden and generated on server/test run into ui/packages/item-picker/components/__generated__
        RepositoryConnection() {
          return {
            edges: [{node: buildRepository({owner: 'github', name: 'repo1'})}],
          }
        },
        Repository() {
          return {
            id: 'repoid123',
            name: 'repo1',
            owner: {
              login: 'github',
            },
          }
        },
      },
    },
    // Tanstack query client that we need is not constructed by renderRelay, so explicit Wrapper does it
    wrapper: Wrapper,
  })

  // Name of the thread in the list, this also makes sure state.threads is populated
  expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

  const message1 = await screen.findByTestId('message-1')
  await within(message1).findByText('Create an issue')

  const message2 = await screen.findByTestId('message-2')
  const confirmationMessage = await within(message2).findByRole('button', {name: /Test title/})
  await user.click(confirmationMessage)

  const tab = await screen.findByRole('tabpanel')
  await within(tab).findByDisplayValue('Test title')
  await within(tab).findByText('Test description')

  const createButton = await within(tab).findByTestId('create-issue-button')
  await user.click(createButton)
  expect(createIssueMutationMock).toHaveBeenCalledTimes(1)
  const calledArgs = createIssueMutationMock.mock.calls[0]![0]
  expect(calledArgs.input.title).toBe('Test title')
  expect(calledArgs.input.body).toBe('Test description\n')

  expect(fetchCount).toBe(fetches.length)
})

test('Rendering existing issue in list and in browser', async () => {
  const fetches = [
    {
      // Immersive chat loads all threads
      request: {url: '/github/chat/threads?', method: 'GET'},
      response: {
        threads: [
          {
            id: '123',
            name: 'Thread Name',
            repoID: 0,
            repoOwnerID: 0,
            associatedRepoIDs: [],
            updatedAt: new Date().toString(),
          },
        ],
      },
    },
    {
      request: {url: '/github/chat/threads/123/messages', method: 'GET'},
      response: {
        thread: {id: '123'},
        messages: [
          {
            id: '1',
            parentMessageID: 'root',
            role: 'user',
            content: 'Show an issue',
            threadID: '123',
          },
          {
            id: '2',
            parentMessageID: '1',
            role: 'assistant',
            content:
              '```list type="issue"\ndata:\n- url: "https://github.com/owner/repo/issues/6633"\n  state: "open"\n  draft: false\n  title: "Existing Issue Title"\n  number: 6633\n  created_at: "2025-04-17T00:00:00Z"\n  closed_at: ""\n  merged_at: ""\n  labels:\n  - "sev2"\n  - "bug"\n  author: "unknown"\n  comments: 0\n  assignees_avatar_urls:\n  - "https://avatars.githubusercontent.com/u/1234?v=4"\n```',
            threadID: '123',
          },
        ],
      },
    },
  ]

  let fetchCount = 0
  mockResponses(fetches, () => fetchCount++)
  const {user} = renderRelay(() => <CopilotImmersiveNoRelay />, {
    relay: {
      queries: {
        IssueViewerViewQuery: {
          type: 'fragment',
          query: IssueViewerViewGraphqlQuery,
          variables: {
            owner: 'owner',
            repo: 'repo',
            number: 6633,
          },
        },
        IssueViewerSecondaryViewQuery: {
          type: 'fragment',
          query: IssueViewerSecondaryGraphqlQuery,
          variables: {
            owner: 'owner',
            repo: 'repo',
            number: 6633,
          },
        },
      },
      mockResolvers: {
        Repository() {
          return {
            issue: {
              number: 6633,
              titleHTML: 'Existing Issue Title',
              // Requires valid date, which is not valid in helper
              createdAt: '2025-01-09',
              // Below fields not constructed by default relay mocks correctly
              milestone: null,
              frontTimelineItems: {
                edges: [],
                totalCount: 0,
              },
              backTimelineItems: {
                edges: [],
                totalCount: 0,
              },
            },
          }
        },
        // Default relay mocks generate duplicate ID for below type, overriding
        Bot() {
          return {id: 'bot123'}
        },
      },
    },
    // Tanstack query client that we need is not constructed by renderRelay, so explicit Wrapper does it
    wrapper: Wrapper,
  })

  // Name of the thread in the list, this also makes sure state.threads is populated
  expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

  const message1 = await screen.findByTestId('message-1')
  await within(message1).findByText('Show an issue')

  const message2 = await screen.findByTestId('message-2')
  const issueLink = await within(message2).findByTestId('issue-list-item-link')
  await within(issueLink).findByText('Existing Issue Title')

  await user.click(issueLink)

  const tab = await screen.findByRole('tabpanel')
  // Disappearing loading indicator is the reliable way to check that form is fully loaded
  await waitForElementToBeRemoved(await within(tab).findByTestId('issue-viewer-loading'))

  const issueTitle = await waitFor(() => within(tab).queryByTestId('issue-title'), {timeout: 1500})
  expect(issueTitle).toHaveTextContent('Existing Issue Title')

  expect(fetchCount).toBe(fetches.length)
})
