import {screen, within} from '@testing-library/react'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, useFragment} from 'react-relay'
import {mockClientEnv} from '@github-ui/client-env/mock'
import {IssueSidebar} from '../IssueSidebar'
import type {IssueSidebarTestQuery} from './__generated__/IssueSidebarTestQuery.graphql'
import type {IssueViewerViewer$key} from '../__generated__/IssueViewerViewer.graphql'
import {issueViewerViewerFragment} from '../IssueViewer'
import {BUTTON_LABELS} from '../../constants/buttons'
import {noop} from '@github-ui/noop'
import type {IssueSidebarLazyTestQuery} from './__generated__/IssueSidebarLazyTestQuery.graphql'
import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import {LABELS} from '../../constants/labels'
import type {IssueSidebarSecondaryTestQuery} from './__generated__/IssueSidebarSecondaryTestQuery.graphql'
import {AliveTestProvider, signChannel} from '@github-ui/use-alive/test-utils'

const optionConfig = {
  singleKeyShortcutsEnabled: true,
  navigate: noop,
}

const channelName = 'issue-thread-subscription-mock-channel'
const mockChannel = signChannel(channelName)

beforeEach(() => {
  jest.clearAllMocks()
})

// eslint-disable-next-line @typescript-eslint/no-unused-expressions
graphql`
  query IssueSidebarLazyTestQuery @relay_test_operation {
    node(id: "test-id") {
      ...IssueSidebarLazySections @dangerously_unaliased_fixme
    }
  }
`

function renderTestComponent({viewerCanType = true, withViewer = true, mockResolversOverrides = {}} = {}) {
  return renderRelay<{
    sidebarQuery: IssueSidebarTestQuery
    lazySidebarQuery: IssueSidebarLazyTestQuery
    secondarySidebarQuery: IssueSidebarSecondaryTestQuery
  }>(
    ({queryData}) => {
      mockClientEnv({
        login: withViewer ? 'monalisa' : undefined,
      })
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, queryData.sidebarQuery.viewer)

      return (
        <AliveTestProvider>
          <IssueSidebar
            sidebarKey={queryData.sidebarQuery.node!}
            viewer={withViewer ? viewer : null}
            optionConfig={optionConfig}
            sidebarSecondaryKey={queryData.secondarySidebarQuery.node!}
          />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {
          sidebarQuery: {
            type: 'fragment',
            query: graphql`
              query IssueSidebarTestQuery @relay_test_operation {
                node(id: "test-id") {
                  ... on Issue {
                    ...IssueSidebarPrimaryQuery @dangerously_unaliased_fixme
                  }
                }
                viewer {
                  ...IssueViewerViewer
                }
              }
            `,
            variables: {},
          },
          lazySidebarQuery: {
            type: 'lazy',
          },
          secondarySidebarQuery: {
            type: 'fragment',
            query: graphql`
              query IssueSidebarSecondaryTestQuery @relay_test_operation {
                node(id: "test-id-2") {
                  ... on Issue {
                    ...IssueSidebarLazySections @dangerously_unaliased_fixme
                    ...IssueSidebarSecondary @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              viewerCanType,
              viewerCanLabel: true,
              viewerCanSetMilestone: true,
              projectItemsNext: {
                edges: [],
              },
              viewerCanLinkBranches: true,
              linkedBranches: {
                nodes: [],
              },
              closedByPullRequestsReferences: {
                nodes: [],
              },
              threadSubscriptionChannel: mockChannel,
            }
          },
          Repository() {
            return {
              issueTypes: [
                {
                  name: 'Bug',
                },
              ],
            }
          },
          Project() {
            // a bit hacky, but needed to not get a coalition error
            return {
              name: 'test',
              title: 'test',
            }
          },
          ...mockResolversOverrides,
        },
      },
      wrapper: Wrapper,
    },
  )
}

describe('rendering', () => {
  test('renders metadata for issue viewer for a logged in user', () => {
    renderTestComponent()

    expect(screen.getByText('Assignees')).toBeInTheDocument()
    expect(screen.getByText('Labels')).toBeInTheDocument()
    expect(screen.getByText('Projects')).toBeInTheDocument()
    expect(screen.getByText('Milestone')).toBeInTheDocument()
    expect(screen.getByText('Development')).toBeInTheDocument()
    expect(screen.getByText('Type')).toBeInTheDocument()
  })

  test('renders metadata for issue viewer for a logged out users', () => {
    renderTestComponent({withViewer: false})

    expect(screen.getByText('Assignees')).toBeInTheDocument()
    expect(screen.getByText('Labels')).toBeInTheDocument()
    expect(screen.getByText('Projects')).toBeInTheDocument()
    expect(screen.getByText('Milestone')).toBeInTheDocument()
    expect(screen.getByText('Development')).toBeInTheDocument()
    expect(screen.getByText('Type')).toBeInTheDocument()
  })

  test('does not render the Notifications section for a logged out user', () => {
    renderTestComponent({withViewer: false})

    expect(screen.queryByText('Notifications')).not.toBeInTheDocument()
  })

  test('does render the Notifications section for a logged in user', () => {
    renderTestComponent()

    expect(screen.getByText('Notifications')).toBeInTheDocument()
  })
})

describe('hotkeys', () => {
  test('opening issue type dialog', async () => {
    const user = setupUserEvent()
    renderTestComponent({withViewer: true})

    expect(screen.queryByText(BUTTON_LABELS.selectType)).not.toBeInTheDocument()

    await user.keyboard('t')

    expect(screen.getByText(BUTTON_LABELS.selectType)).toBeInTheDocument()
  })

  test('opening development picker', async () => {
    const user = setupUserEvent()
    renderTestComponent({withViewer: true})

    expect(screen.getByText('Development')).toBeInTheDocument()
    expect(screen.getByText(LABELS.development.createBranch)).toBeInTheDocument()
    expect(screen.getByText(LABELS.development.createBranchSuffix)).toBeInTheDocument()

    // only visibile after picker is open
    expect(screen.queryByText(LABELS.development.prsBranchesPickerSubtitle)).not.toBeInTheDocument()

    await user.keyboard('d')

    const pickerOverlay = screen.getByRole('dialog')
    const pickerSubtitle = within(pickerOverlay).getByText(LABELS.development.prsBranchesPickerSubtitle, {exact: false})
    expect(pickerSubtitle).toBeVisible()

    const input = within(pickerOverlay).getByRole('combobox')
    expect(input).toHaveTextContent('')
  })

  test('open label picker', async () => {
    renderTestComponent({withViewer: true})
    const user = setupUserEvent()

    await user.keyboard('l')
    const dialog = within(screen.getByRole('dialog'))

    expect(dialog.getByText('Apply labels to this issue')).toBeInTheDocument()

    const input = dialog.getByRole('combobox')
    expect(input).toHaveTextContent('')
  })

  test('opening milestone picker', async () => {
    renderTestComponent({withViewer: true})
    const user = setupUserEvent()

    await user.keyboard('m')

    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText('Set milestone')).toBeInTheDocument()

    const input = dialog.getByRole('combobox')
    expect(input).toHaveTextContent('')
  })
})

describe('graceful degradation', () => {
  test('renders Projects fallback when no projectItemsNext are returned', () => {
    // Suppress console.error which we rethrow in the error boundary
    jest.spyOn(console, 'error').mockImplementation()

    renderTestComponent({
      withViewer: false,
      mockResolversOverrides: {
        Issue() {
          return {viewerCanType: true, projectItemsNext: null}
        },
      },
    })

    expect(screen.getByText('Projects are currently unavailable')).toBeInTheDocument()
  })
})
