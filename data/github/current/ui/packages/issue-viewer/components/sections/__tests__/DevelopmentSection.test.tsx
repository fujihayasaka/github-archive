import {Wrapper} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {fetchQuery, graphql} from 'react-relay'

import {DevelopmentSection} from '../development-section/DevelopmentSection'
import {TEST_IDS} from '../../../constants/test-ids'
import {LABELS} from '../../../constants/labels'
import {renderRelay} from '@github-ui/relay-test-utils'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {DevelopmentSectionTestQuery} from './__generated__/DevelopmentSectionTestQuery.graphql'
import type {DevelopmentPickerQuery} from '../development-section/__generated__/DevelopmentPickerQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {Observable} from 'relay-runtime'
import safeStorage from '@github-ui/safe-storage'
import {verifiedFetch} from '@github-ui/verified-fetch'

jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlag: jest.fn(),
}))
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

jest.mock('relay-runtime', () => ({
  ...jest.requireActual('relay-runtime'),
  fetchQuery: jest.fn().mockReturnValue({
    subscribe: jest.fn(),
  }),
}))

jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const mockVerifiedFetch = jest.mocked(verifiedFetch)
const mockFetchQuery = jest.mocked(fetchQuery)

const DevelopmentSectionGraphqlTestQuery = graphql`
  query DevelopmentSectionTestQuery($owner: String!, $repo: String!, $number: Int!) @relay_test_operation {
    repository(owner: $owner, name: $repo) {
      issue(number: $number) {
        ...DevelopmentSectionFragment
      }
    }
  }
`

type DevelopmentSectionQueries = {
  developmentSectionQuery: DevelopmentSectionTestQuery
  developmentPickerQuery: DevelopmentPickerQuery
}

const developmentSectionRelayMock: RelayMockProps<DevelopmentSectionQueries> = {
  queries: {
    developmentSectionQuery: {
      type: 'fragment',
      query: DevelopmentSectionGraphqlTestQuery,
      variables: {
        owner: 'owner',
        repo: 'repo',
        number: 1,
      },
    },
    developmentPickerQuery: {
      type: 'lazy',
    },
  },
}

test('renders 3 linked pull requests and 2 linked branches', async () => {
  renderRelay<DevelopmentSectionQueries>(
    ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
    {
      relay: {
        ...developmentSectionRelayMock,
        mockResolvers: {
          Issue: () => ({
            linkedBranches: {
              nodes: Array(2).fill(undefined),
            },
            closedByPullRequestsReferences: {
              nodes: Array(3).fill(undefined),
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  // Find the pull requests and linked branches
  const pullRequests = await screen.findByTestId(TEST_IDS.linkedPullRequestContainer)
  expect(within(pullRequests).getAllByRole('listitem').length).toBe(5)
})

describe('Button conditional rendering for permissions', () => {
  test('renders no buttons without permissions', async () => {
    renderRelay<DevelopmentSectionQueries>(
      ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...developmentSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              viewerCanLinkBranches: false,
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.queryByText('Create a branch')).not.toBeInTheDocument()
    expect(screen.getByText(LABELS.emptySections.development)).toBeInTheDocument()
  })

  test('renders edit button if edit permitted and the data is loaded', () => {
    renderRelay<DevelopmentSectionQueries>(
      ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...developmentSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              viewerCanLinkBranches: true,
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByText('Create a branch')).toBeInTheDocument()
    expect(screen.queryByText(LABELS.emptySections.development)).not.toBeInTheDocument()
  })
})

test('opens last active picker with single key shortcuts', async () => {
  const {user} = renderRelay<DevelopmentSectionQueries>(
    ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
    {
      relay: {
        ...developmentSectionRelayMock,
        mockResolvers: {
          Issue: () => ({
            viewerCanLinkBranches: true,
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  const repoPickerDescription = 'Select a repository to search for branches and pull requests'
  const pullsPickerBackButtonLabel = 'Return to repository picker'

  // Expect pulls/branches picker to be open after pressing 'd'
  await user.keyboard('d')

  expect(
    screen.queryByLabelText(repoPickerDescription, {
      exact: false,
    }),
  ).not.toBeInTheDocument()

  const repoPickerBackButton = screen.getByLabelText(pullsPickerBackButtonLabel)
  expect(repoPickerBackButton).toBeInTheDocument()

  // Change to the repo picker
  await user.click(repoPickerBackButton)
  await user.keyboard('Escape')

  // Expect repo picker to be open after pressing 'd'
  await user.keyboard('d')
  expect(screen.queryByLabelText(pullsPickerBackButtonLabel)).not.toBeInTheDocument()
  expect(screen.getByText(repoPickerDescription, {exact: false})).toBeInTheDocument()
})

test('renders draft PRs correctly', async () => {
  renderRelay<DevelopmentSectionQueries>(
    ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
    {
      relay: {
        ...developmentSectionRelayMock,
        mockResolvers: {
          Issue: () => ({
            linkedBranches: {
              nodes: [],
            },
            closedByPullRequestsReferences: {
              nodes: [
                {
                  id: 'PR-ID',
                  isDraft: true,
                  isInMergeQueue: false,
                  title: 'Closed Draft PR',
                  url: 'mock-url',
                  state: 'CLOSED',
                },
                {
                  id: 'PR-ID-2',
                  isDraft: true,
                  isInMergeQueue: false,
                  title: 'Open Draft PR',
                  url: 'mock-url',
                  state: 'OPEN',
                },
                {
                  id: 'PR-ID-3',
                  isDraft: true,
                  isInMergeQueue: false,
                  title: 'Merged Draft PR',
                  url: 'mock-url',
                  state: 'MERGED',
                },
              ],
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  // Find all the linked PRs
  const pullRequests = await screen.findByTestId(TEST_IDS.linkedPullRequestContainer)
  expect(within(pullRequests).getAllByRole('listitem').length).toBe(3)

  // Find the draft and open linked PR
  const draft = await within(pullRequests).findAllByLabelText('Draft')
  expect(draft.length).toBe(1)

  // Find the draft and closed linked PR
  const closedDraft = await within(pullRequests).findAllByLabelText('Closed')
  expect(closedDraft.length).toBe(1)

  // Find the draft and merged linked PR
  const mergedDraft = await within(pullRequests).findAllByLabelText('Merged')
  expect(mergedDraft.length).toBe(1)
})

describe('Open in Copilot Agent button', () => {
  test('does not render the button when the feature flag is disabled', async () => {
    mockUseFeatureFlag.mockImplementation((featureName: string) => featureName !== 'copilot_agent_mode')

    renderRelay<DevelopmentSectionQueries>(
      ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...developmentSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              viewerCanLinkBranches: true,
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    const button = screen.queryByTestId('open-in-copilot-agent-button')
    expect(button).not.toBeInTheDocument()
  })

  test('renders the button when the feature flag is enabled', async () => {
    mockUseFeatureFlag.mockImplementation((featureName: string) => featureName === 'copilot_agent_mode')

    renderRelay<DevelopmentSectionQueries>(
      ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...developmentSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              viewerCanLinkBranches: true,
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    const button = await screen.findByTestId('open-in-copilot-agent-button')
    expect(button).toBeInTheDocument()
  })

  test('send request to Codespace endpoint when clicking the "Open in Copilot Agent Mode" button', async () => {
    mockUseFeatureFlag.mockImplementation((featureName: string) => featureName === 'copilot_agent_mode')

    // Mock the fetchQuery response
    const mockResponse = {
      node: {
        __typename: 'Repository',
        databaseId: 123,
        defaultBranchRef: {
          name: 'main',
        },
      },
    }

    // Mock fetchQuery to return a RelayObservable
    mockFetchQuery.mockImplementation(() =>
      Observable.create(sink => {
        sink.next(mockResponse)
        sink.complete()
      }),
    )

    const safeLocalStorage = safeStorage('localStorage')
    safeLocalStorage.setItem('vscs_target', '"vscs_target_value"')
    safeLocalStorage.setItem('vscs_target_url', '"vscs_target_url_value"')

    const {user} = renderRelay<DevelopmentSectionQueries>(
      ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...developmentSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              viewerCanLinkBranches: true,
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    const button = await screen.findByTestId('open-in-copilot-agent-button')
    expect(button).toBeInTheDocument()

    await user.click(button)

    // Verify the fetchQuery call
    expect(fetchQuery).toHaveBeenCalledWith(expect.anything(), expect.anything(), {
      id: '<Repository-mock-id-1>',
    })

    // Verify a POST request was made via verifiedFetch
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/codespaces/', {
      method: 'POST',
      body: expect.any(FormData),
    })

    // Check the FormData content
    expect(mockVerifiedFetch).toHaveBeenCalled()
    const formData = mockVerifiedFetch.mock.calls[0]![1]!.body as FormData
    expect(formData.get('codespace[repository_id]')).toBe('123')
    expect(formData.get('codespace[ref]')).toBe('main')
    expect(formData.get('codespace[issue_id]')).toBe('42')
    expect(formData.get('codespace[vscs_target]')).toBe('vscs_target_value')
    expect(formData.get('codespace[vscs_target_url]')).toBe('vscs_target_url_value')
  })

  test('displays a banner upon Codespace creation error', async () => {
    mockUseFeatureFlag.mockImplementation((featureName: string) => featureName === 'copilot_agent_mode')

    const mockResponse = {
      node: {
        __typename: 'Repository',
        databaseId: 123,
        defaultBranchRef: {
          name: 'main',
        },
      },
    }

    mockFetchQuery.mockImplementation(() =>
      Observable.create(sink => {
        sink.next(mockResponse)
        sink.complete()
      }),
    )

    const safeLocalStorage = safeStorage('localStorage')
    safeLocalStorage.setItem('vscs_target', '"vscs_target_value"')
    safeLocalStorage.setItem('vscs_target_url', '"vscs_target_url_value"')

    const {user} = renderRelay<DevelopmentSectionQueries>(
      ({queryData}) => <DevelopmentSection issue={queryData.developmentSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...developmentSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              viewerCanLinkBranches: true,
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    const button = await screen.findByTestId('open-in-copilot-agent-button')
    expect(button).toBeInTheDocument()

    await user.click(button)

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

    expect(mockVerifiedFetch).toHaveBeenCalled()
    expect(screen.getByText('Codespace creation failed')).toBeInTheDocument()
  })
})
